import AppKit
import AVFoundation
import ApplicationServices
import CoreGraphics

extension Notification.Name {
    static let permissionsChanged = Notification.Name("flowlocal.permissionsChanged")
}

/// The four macOS permissions FlowLocal can use, each with the one System Settings pane that controls it.
enum Permission: String, CaseIterable, Identifiable {
    case microphone, accessibility, inputMonitoring, screenRecording
    var id: String { rawValue }

    var title: String {
        switch self {
        case .microphone: return "Microfone"
        case .accessibility: return "Acessibilidade"
        case .inputMonitoring: return "Monitoramento de Entrada"
        case .screenRecording: return "Gravação de Tela"
        }
    }

    /// Name of the list entry to switch on in System Settings.
    var pane: String {
        switch self {
        case .microphone: return "Privacidade e Segurança → Microfone"
        case .accessibility: return "Privacidade e Segurança → Acessibilidade"
        case .inputMonitoring: return "Privacidade e Segurança → Monitoramento de Entrada"
        case .screenRecording: return "Privacidade e Segurança → Gravação de Tela e Áudio do Sistema"
        }
    }

    var why: String {
        switch self {
        case .microphone: return "Para ouvir sua voz enquanto você segura a tecla de ditado."
        case .accessibility: return "Para colar o texto no app em foco e ler o campo de texto e a seleção."
        case .inputMonitoring: return "Para perceber quando você aperta e solta a tecla de ditado em qualquer app."
        case .screenRecording: return "Só para a leitura opcional da tela (OCR). Tudo é processado no seu Mac."
        }
    }

    var settingsURL: URL {
        let key: String
        switch self {
        case .microphone: key = "Privacy_Microphone"
        case .accessibility: key = "Privacy_Accessibility"
        case .inputMonitoring: key = "Privacy_ListenEvent"
        case .screenRecording: key = "Privacy_ScreenCapture"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(key)")!
    }

    var isGranted: Bool {
        switch self {
        case .microphone: return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        case .accessibility: return AXIsProcessTrusted()
        case .inputMonitoring: return CGPreflightListenEventAccess()
        case .screenRecording: return CGPreflightScreenCaptureAccess()
        }
    }

    /// Steps the guide walks through, in order. Screen Recording only matters when OCR is switched on.
    static var guideSteps: [Permission] {
        [.microphone, .accessibility, .inputMonitoring] + (Settings.screenOCR ? [.screenRecording] : [])
    }

    /// Triggers the system prompt where macOS offers one, and opens the matching pane.
    func request() {
        switch self {
        case .microphone:
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                AVCaptureDevice.requestAccess(for: .audio) { _ in }
                return
            }
        case .accessibility:
            _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        case .inputMonitoring:
            _ = CGRequestListenEventAccess()
        case .screenRecording:
            _ = CGRequestScreenCaptureAccess()
        }
        NSWorkspace.shared.open(settingsURL)
    }
}

/// Live permission state, refreshed every second so the guide ticks a step the moment you switch it on.
final class PermissionsModel: ObservableObject {
    static let shared = PermissionsModel()
    @Published private(set) var granted: [Permission: Bool] = [:]
    private var timer: Timer?

    private init() {
        refresh(initial: true)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh(initial: false) }
    }

    /// First step not yet granted, i.e. the one the guide shows.
    var currentStep: Permission? { Permission.guideSteps.first { granted[$0] != true } }

    func refresh(initial: Bool) {
        var next: [Permission: Bool] = [:]
        for p in Permission.allCases { next[p] = p.isGranted }
        guard next != granted else { return }
        for p in Permission.allCases where next[p] != granted[p] {
            Log.write("permission \(p.rawValue): \(granted[p].map(String.init(describing:)) ?? "unknown") -> \(next[p] ?? false)")
        }
        granted = next
        if !initial { NotificationCenter.default.post(name: .permissionsChanged, object: nil) }
    }
}
