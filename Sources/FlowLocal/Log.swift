import Foundation

/// Small append-only diagnostic log (modifier key codes, permission states, pipeline stages and errors; never dictated text).
enum Log {
    static let url = Paths.support.appendingPathComponent("flowlocal.log")
    private static let queue = DispatchQueue(label: "flowlocal.log")
    private static let stamp = ISO8601DateFormatter()

    static func write(_ message: String) {
        queue.async {
            let line = "\(stamp.string(from: Date())) \(message)\n"
            if let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 512_000 {
                try? FileManager.default.removeItem(at: url)   // crude rotation
            }
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
            } else {
                try? line.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}
