import AppKit
import ApplicationServices
import ScreenCaptureKit
import Vision

/// What is on screen around the cursor when you start talking. Used locally (never sent anywhere) to:
/// bias whisper toward names that appear on screen, give the LLM context, and fit the dictated text to the field.
struct ScreenContext {
    var appName = ""
    var windowTitle = ""
    /// Text of the focused field before / after the caret (Accessibility).
    var before = ""
    var after = ""
    /// Text recognised on the focused window (optional OCR).
    var ocr = ""

    var isEmpty: Bool { before.isEmpty && after.isEmpty && ocr.isEmpty && windowTitle.isEmpty }

    // MARK: Terms

    /// Likely names and jargon seen on screen (capitalised or camelCase words), most frequent first.
    var terms: [String] {
        let text = [windowTitle, before, after, ocr].joined(separator: "\n")
        guard let re = try? NSRegularExpression(pattern: #"\b(?:[A-ZÀ-Ý][\p{L}\d]{2,}|[a-z]+[A-Z][\p{L}\d]*)\b"#) else { return [] }
        var count: [String: Int] = [:]
        for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            if let r = Range(m.range, in: text) { count[String(text[r]), default: 0] += 1 }
        }
        return count.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(24).map(\.key)
    }

    /// Text appended to whisper's initial prompt (whisper only reads the last ~220 tokens, so keep it short).
    var whisperHint: String {
        let joined = terms.joined(separator: ", ")
        return joined.isEmpty ? "" : " " + String(joined.prefix(350)) + "."
    }

    /// Untrusted screen text for the LLM prompt, wrapped so it cannot close its own tag.
    var promptBlock: String {
        func clean(_ s: String, _ n: Int) -> String {
            String(s.suffix(n)).replacingOccurrences(of: "</screen_context>", with: "")
        }
        var lines: [String] = []
        if !appName.isEmpty { lines.append("App: \(appName)") }
        if !windowTitle.isEmpty { lines.append("Janela: \(clean(windowTitle, 120))") }
        if !before.isEmpty { lines.append("Texto antes do cursor: «\(clean(before, 500))»") }
        if !after.isEmpty { lines.append("Texto depois do cursor: «\(String(clean(after, 200)))»") }
        if !ocr.isEmpty { lines.append("Texto visível na janela: «\(clean(ocr, 1200))»") }
        return lines.joined(separator: "\n")
    }

    // MARK: Accessibility (fast, no extra permission)

    static func fromAccessibility(app: NSRunningApplication?) -> ScreenContext {
        var ctx = ScreenContext(appName: app?.localizedName ?? "")
        guard AXIsProcessTrusted() else { return ctx }

        if let pid = app?.processIdentifier,
           let window = attribute(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute) {
            ctx.windowTitle = attribute(window as! AXUIElement, kAXTitleAttribute) as? String ?? ""
        }

        guard let focused = attribute(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute) else { return ctx }
        let element = focused as! AXUIElement
        // Never read password fields.
        if (attribute(element, kAXSubroleAttribute) as? String) == "AXSecureTextField" { return ctx }
        guard let value = attribute(element, kAXValueAttribute) as? String, !value.isEmpty else { return ctx }

        let ns = value as NSString
        var caret = ns.length
        if let r = attribute(element, kAXSelectedTextRangeAttribute), CFGetTypeID(r) == AXValueGetTypeID() {
            var range = CFRange()
            if AXValueGetValue(r as! AXValue, .cfRange, &range) { caret = range.location }
        }
        caret = min(max(caret, 0), ns.length)
        let start = max(0, caret - 600), end = min(ns.length, caret + 200)
        ctx.before = ns.substring(with: NSRange(location: start, length: caret - start))
        ctx.after = ns.substring(with: NSRange(location: caret, length: end - caret))
        return ctx
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    // MARK: OCR (optional; needs Screen Recording permission)

    static func ocr(app: NSRunningApplication?) async -> String {
        guard CGPreflightScreenCaptureAccess(), let pid = app?.processIdentifier else { return "" }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            guard let window = content.windows
                .filter({ $0.owningApplication?.processID == pid && $0.frame.width > 200 && $0.frame.height > 150 })
                .max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else { return "" }
            let config = SCStreamConfiguration()
            let scale = min(2, 2400 / max(window.frame.width, 1))
            config.width = Int(window.frame.width * scale)
            config.height = Int(window.frame.height * scale)
            config.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window),
                                                                   configuration: config)
            return recognize(image)
        } catch {
            Log.write("ocr failed: \(error.localizedDescription)")
            return ""
        }
    }

    private static var warmed = false

    /// Vision loads its text models on first use (~30 s once, 0.1 s after), far beyond the time dictation can wait.
    /// Running one throwaway recognition in the background keeps the first real OCR fast.
    static func warmUpOCR() {
        guard !warmed else { return }
        warmed = true
        Task.detached(priority: .utility) {
            let image = NSImage(size: NSSize(width: 240, height: 60), flipped: false) { rect in
                NSColor.white.setFill(); rect.fill()
                ("Warm up FlowLocal" as NSString).draw(at: NSPoint(x: 8, y: 16),
                    withAttributes: [.font: NSFont.systemFont(ofSize: 22), .foregroundColor: NSColor.black])
                return true
            }
            if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                let t0 = Date()
                _ = recognize(cg)
                Log.write(String(format: "ocr warmed up in %.1fs", Date().timeIntervalSince(t0)))
            }
        }
    }

    static func recognize(_ image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["pt-BR", "en-US"]
        try? VNImageRequestHandler(cgImage: image).perform([request])
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return String(lines.joined(separator: "\n").prefix(3000))
    }

    /// Waits for a background OCR task, giving up after `timeout` seconds so dictation is never held up.
    static func result(of task: Task<String, Never>, timeout: Double) async -> String {
        await withTaskGroup(of: String?.self) { group in
            group.addTask { await task.value }
            group.addTask { try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000)); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? ""
        }
    }
}

/// Fits dictated text to the field it lands in: the space after the caret's neighbour and mid-sentence casing.
enum ContextFit {
    static func fit(_ text: String, to ctx: ScreenContext?, knownTerms: [String]) -> String {
        guard let before = ctx?.before, !before.isEmpty, let first = text.first, !text.hasPrefix(" "), !text.hasPrefix("\n") else { return text }
        var t = text

        // Continuing a sentence: "…vou ao" + "Mercado" -> "mercado" (unless it looks like a name or acronym).
        let lastVisible = before.last { !$0.isWhitespace && !$0.isNewline }
        let atLineStart = before.reversed().first { !$0.isWhitespace || $0.isNewline }.map(\.isNewline) ?? true
        if let last = lastVisible, !atLineStart, !".!?…:;".contains(last), first.isUppercase {
            let word = String(t.prefix { $0.isLetter || $0.isNumber })
            let rest = word.dropFirst()
            let looksPlain = word.count > 1 && rest == rest.lowercased()
            let isKnown = knownTerms.contains { $0.caseInsensitiveCompare(word) == .orderedSame }
            if looksPlain && !isKnown { t = first.lowercased() + t.dropFirst() }
        }

        // Keep words from gluing together when the caret sits right after a non-space character.
        if let last = before.last, !last.isWhitespace, !last.isNewline, !"([{\"'“‘«/-".contains(last),
           let nextFirst = t.first, !",.;:!?)]}".contains(nextFirst) {
            t = " " + t
        }
        return t
    }
}
