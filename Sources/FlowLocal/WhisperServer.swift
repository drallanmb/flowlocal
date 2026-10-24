import Foundation

/// Owns a local `whisper-server` (whisper.cpp, Metal) process so the model stays loaded between dictations.
final class WhisperServer {
    enum Failure: LocalizedError {
        case missingBinary(String)
        case missingModel(String)
        case notReady
        case http(Int, String)

        var errorDescription: String? {
            switch self {
            case .missingBinary(let p): return "whisper-server não encontrado em \(p). Rode: brew install whisper.cpp"
            case .missingModel(let p): return "Modelo não encontrado: \(p)"
            case .notReady: return "Servidor de transcrição ainda carregando o modelo"
            case .http(let c, let m): return "Servidor respondeu \(c): \(m)"
            }
        }
    }

    private var process: Process?
    private(set) var isReady = false
    private let base = URL(string: "http://127.0.0.1:\(Settings.port)")!

    func start(completion: @escaping (Result<Void, Error>) -> Void) {
        stop()
        let bin = Settings.whisperServerPath
        let model = Paths.models.appendingPathComponent(Settings.modelFile).path
        guard FileManager.default.isExecutableFile(atPath: bin) else { return completion(.failure(Failure.missingBinary(bin))) }
        guard FileManager.default.fileExists(atPath: model) else { return completion(.failure(Failure.missingModel(model))) }

        // A previous instance that was force-quit can leave its server holding the port.
        let stale = Process()
        stale.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        stale.arguments = ["-f", "whisper-server.*--port \(Settings.port)"]
        try? stale.run(); stale.waitUntilExit()

        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = [
            "-m", model,
            "--host", "127.0.0.1",
            "--port", String(Settings.port),
            "-l", "auto",           // overridden per request
            "-nt",                  // no timestamps in text
            "-sns",                 // suppress non-speech tokens like [MUSIC]
            "-t", "4",
        ]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        p.terminationHandler = { [weak self] _ in self?.isReady = false }
        do { try p.run() } catch { return completion(.failure(error)) }
        process = p

        // Poll until the HTTP port answers (model load takes a few seconds).
        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            for _ in 0..<120 {
                if !(self.process?.isRunning ?? false) { break }
                var req = URLRequest(url: self.base)
                req.timeoutInterval = 1
                let sem = DispatchSemaphore(value: 0)
                var ok = false
                URLSession.shared.dataTask(with: req) { _, resp, _ in ok = resp != nil; sem.signal() }.resume()
                _ = sem.wait(timeout: .now() + 2)
                if ok { self.isReady = true; return completion(.success(())) }
                Thread.sleep(forTimeInterval: 0.5)
            }
            completion(.failure(Failure.notReady))
        }
    }

    func stop() {
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
        isReady = false
    }

    /// Sends a WAV to whisper-server and returns the raw transcript.
    func transcribe(wav: Data, language: String, prompt: String) async throws -> String {
        guard isReady else { throw Failure.notReady }
        let boundary = "flowlocal-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wav)
        body.append("\r\n".data(using: .utf8)!)
        field("response_format", "json")
        field("temperature", "0.0")
        field("language", language)
        if !prompt.isEmpty { field("prompt", prompt) }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var req = URLRequest(url: base.appendingPathComponent("inference"))
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw Failure.http(code, String(data: data, encoding: .utf8) ?? "") }
        struct R: Decodable { let text: String? }
        return (try JSONDecoder().decode(R.self, from: data).text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
