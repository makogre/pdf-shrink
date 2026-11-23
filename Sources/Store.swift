import Foundation
import PDFKit
import SwiftUI

@MainActor
final class FileItem: ObservableObject, Identifiable {
    enum State: Equatable {
        case queued, running, done, failed(Failure)
        var isBusy: Bool { self == .queued || self == .running }
    }

    let id = UUID()
    let url: URL
    let originalSize: Int64

    @Published var state: State = .queued
    @Published var page = 0
    @Published var pages = 0
    @Published var newSize: Int64?
    /// Neuschreiben hätte die Datei vergrößert — wir liefern das Original.
    @Published var usedOriginal = false
    @Published var savedURL: URL?

    /// Ergebnis im Zwischenordner, bis der Nutzer speichert.
    var outputURL: URL?
    var run: GSRun?

    init(url: URL, originalSize: Int64) {
        self.url = url
        self.originalSize = originalSize
    }

    var name: String { url.lastPathComponent }

    var suggestedName: String {
        let stem = url.deletingPathExtension().lastPathComponent
        return usedOriginal ? name : "\(stem)_komprimiert.pdf"
    }

    var progress: Double {
        switch state {
        case .queued:  return 0
        case .running: return pages > 0 ? Double(page) / Double(pages) : 0
        case .done, .failed: return 1
        }
    }

    var savedFraction: Double {
        guard let newSize else { return 0 }
        return Fmt.savedFraction(from: originalSize, to: newSize)
    }
}

@MainActor
final class Store: ObservableObject {
    @Published var items: [FileItem] = []
    @Published var settings = Settings()
    /// Oberflächensprache; die Wahl überlebt den Neustart.
    @Published var lang: Lang = .initial {
        didSet { UserDefaults.standard.set(lang.rawValue, forKey: "language") }
    }
    /// Alle sichtbaren Texte der aktuellen Sprache.
    var s: Strings { lang.strings }
    /// Ergebnis sofort neben das Original legen, ohne Nachfrage.
    @Published var autoSave = false

    private let tempRoot: URL = {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PDFShrink-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private var running = 0
    private let maxConcurrent = 2
    private var waiting: [FileItem] = []

    deinit {
        let dir = tempRoot
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - Dateien aufnehmen

    func add(urls: [URL]) {
        for url in urls where url.pathExtension.lowercased() == "pdf" {
            let std = url.standardizedFileURL
            // Dieselbe Datei nicht doppelt in die Liste nehmen
            if items.contains(where: { $0.url == std && $0.state.isBusy }) { continue }
            let size = (try? FileManager.default.attributesOfItem(atPath: std.path)[.size] as? Int64) ?? nil
            let item = FileItem(url: std, originalSize: size ?? 0)
            items.append(item)
            enqueue(item)
        }
    }

    func clearFinished() {
        items.removeAll { !$0.state.isBusy }
    }

    func remove(_ item: FileItem) {
        item.run?.cancel()
        items.removeAll { $0.id == item.id }
    }

    // MARK: - Warteschlange

    func recompressAll() {
        for item in items where !item.state.isBusy { enqueue(item) }
    }

    func enqueue(_ item: FileItem) {
        item.state = .queued
        item.page = 0
        item.newSize = nil
        item.usedOriginal = false
        item.savedURL = nil
        waiting.append(item)
        pump()
    }

    private func pump() {
        while running < maxConcurrent, !waiting.isEmpty {
            let item = waiting.removeFirst()
            running += 1
            Task { [weak self] in
                await self?.process(item)
                self?.running -= 1
                self?.pump()
            }
        }
    }

    private func process(_ item: FileItem) async {
        item.state = .running

        // Vorab prüfen: lesbar? verschlüsselt? wie viele Seiten?
        guard FileManager.default.isReadableFile(atPath: item.url.path) else {
            item.state = .failed(.noAccess)
            return
        }
        if let doc = PDFDocument(url: item.url) {
            item.pages = doc.pageCount
            if doc.isLocked {
                item.state = .failed(.passwordProtected)
                return
            }
        } else {
            item.state = .failed(.notReadablePDF)
            return
        }

        let output = tempRoot.appendingPathComponent("\(item.id.uuidString).pdf")
        let run = GSRun()
        item.run = run
        let settings = self.settings

        do {
            try await run.run(settings: settings, input: item.url, output: output,
                              onTotal: { [weak item] n in
                                  Task { @MainActor in item?.pages = n }
                              },
                              onPage: { [weak item] n in
                                  Task { @MainActor in item?.page = n }
                              })

            let size = (try? FileManager.default.attributesOfItem(atPath: output.path)[.size] as? Int64) ?? nil
            guard let produced = size else {
                item.state = .failed(.noOutput)
                return
            }

            if produced >= item.originalSize {
                // Neuschreiben hat nichts gebracht — Original weiterreichen.
                try? FileManager.default.removeItem(at: output)
                try? FileManager.default.copyItem(at: item.url, to: output)
                item.usedOriginal = true
                item.newSize = item.originalSize
            } else {
                item.newSize = produced
            }

            item.outputURL = output
            item.page = item.pages
            item.state = .done
            if autoSave { _ = saveNextToOriginal(item) }
        } catch let failure as Failure {
            item.state = .failed(failure)
        } catch {
            item.state = .failed(.gsFailed(code: -1, detail: error.localizedDescription))
        }
        item.run = nil
    }

    // MARK: - Speichern

    @discardableResult
    func saveNextToOriginal(_ item: FileItem) -> URL? {
        guard let src = item.outputURL else { return nil }
        let folder = item.url.deletingLastPathComponent()
        let dest = uniqueURL(in: folder, name: item.suggestedName)
        do {
            try FileManager.default.copyItem(at: src, to: dest)
            item.savedURL = dest
            return dest
        } catch {
            item.state = .failed(.saveFailed(error.localizedDescription))
            return nil
        }
    }

    func save(_ item: FileItem, to dest: URL) {
        guard let src = item.outputURL else { return }
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: src, to: dest)
            item.savedURL = dest
        } catch {
            item.state = .failed(.saveFailed(error.localizedDescription))
        }
    }

    private func uniqueURL(in folder: URL, name: String) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = folder.appendingPathComponent(name)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) (\(n)).\(ext)")
            n += 1
        }
        return candidate
    }

    // MARK: - Summen

    var finished: [FileItem] { items.filter { $0.state == .done } }

    var totalBefore: Int64 { finished.reduce(0) { $0 + $1.originalSize } }
    var totalAfter: Int64 { finished.reduce(0) { $0 + ($1.newSize ?? 0) } }
}
