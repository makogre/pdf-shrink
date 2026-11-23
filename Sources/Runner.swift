import Foundation

/// Ein einzelner Ghostscript-Lauf. Meldet den Seitenfortschritt, den gs auf
/// stdout ausgibt ("Processing pages 1 through N." / "Page n").
final class GSRun: @unchecked Sendable {

    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    func cancel() {
        let p: Process? = withLock {
            cancelled = true
            return process
        }
        p?.terminate()
    }

    /// Gesperrter Zugriff in einer synchronen Funktion gekapselt: NSLock darf
    /// nicht direkt aus einem async-Kontext gesperrt werden.
    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    /// Prozess übernehmen; wirft, wenn zwischenzeitlich abgebrochen wurde.
    private func adopt(_ proc: Process) throws {
        try withLock {
            if cancelled { throw GSError.cancelled }
            process = proc
        }
    }

    func run(settings: Settings,
             input: URL,
             output: URL,
             onTotal: @escaping @Sendable (Int) -> Void,
             onPage: @escaping @Sendable (Int) -> Void) async throws {

        guard let gs = Ghostscript.executableURL else { throw GSError.notInstalled }

        let proc = Process()
        proc.executableURL = gs
        proc.arguments = Ghostscript.arguments(settings: settings, input: input, output: output)

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        // Letzte Ausgabezeilen aufheben, um im Fehlerfall etwas Brauchbares zu zeigen
        let tail = TailBuffer()

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            tail.feed(data) { line in
                if let n = Self.totalPages(in: line) { onTotal(n) }
                if let n = Self.currentPage(in: line) { onPage(n) }
            }
        }

        try adopt(proc)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            proc.terminationHandler = { p in
                pipe.fileHandleForReading.readabilityHandler = nil
                // Rest im Puffer noch auswerten
                let rest = pipe.fileHandleForReading.availableData
                if !rest.isEmpty { tail.feed(rest) { _ in } }

                if p.terminationReason == .uncaughtSignal {
                    cont.resume(throwing: GSError.cancelled)
                } else if p.terminationStatus != 0 {
                    cont.resume(throwing: GSError.failed(code: p.terminationStatus,
                                                         detail: tail.summary()))
                } else {
                    cont.resume()
                }
            }
            do {
                try proc.run()
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                cont.resume(throwing: error)
            }
        }
    }

    // MARK: - Ausgabe deuten

    private static func totalPages(in line: String) -> Int? {
        // "Processing pages 1 through 12."
        guard line.hasPrefix("Processing pages ") else { return nil }
        let parts = line.split(separator: " ")
        guard let idx = parts.firstIndex(of: "through"), idx + 1 < parts.count else { return nil }
        return Int(parts[idx + 1].trimmingCharacters(in: CharacterSet(charactersIn: ".")))
    }

    private static func currentPage(in line: String) -> Int? {
        // "Page 3"
        guard line.hasPrefix("Page ") else { return nil }
        return Int(line.dropFirst(5).prefix(while: \.isNumber))
    }
}

/// Zerlegt den Stream in Zeilen und hält die letzten davon fest.
private final class TailBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var partial = Data()
    private var lines: [String] = []

    func feed(_ data: Data, _ each: (String) -> Void) {
        lock.lock()
        partial.append(data)
        var produced: [String] = []
        while let nl = partial.firstIndex(of: 0x0A) {
            let chunk = partial.subdata(in: partial.startIndex..<nl)
            partial.removeSubrange(partial.startIndex...nl)
            if let s = String(data: chunk, encoding: .utf8) {
                produced.append(s.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        lines.append(contentsOf: produced)
        if lines.count > 40 { lines.removeFirst(lines.count - 40) }
        lock.unlock()
        produced.forEach(each)
    }

    func summary() -> String {
        lock.lock(); defer { lock.unlock() }
        return lines
            .filter {
                !$0.isEmpty
                && !$0.hasPrefix("Page ")
                && !$0.hasPrefix("Processing pages")
                // PostScript-Stack-Dumps sind fuer Nutzer wertlos
                && !$0.hasPrefix("--")
                && !$0.contains("dict:")
                && !$0.hasPrefix("GPL Ghostscript")
            }
            .suffix(3)
            .joined(separator: " / ")
    }
}
