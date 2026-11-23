import Foundation

// Prüft Argumentbau, QFactor-Kennlinie und einen echten Ghostscript-Lauf
// inklusive Fortschritts-Auswertung. Nutzt dieselben Quellen wie die App.
@main struct SelfTest {
    static func main() async {
        let input = URL(fileURLWithPath: CommandLine.arguments[1])
        var failures = 0
        func check(_ label: String, _ ok: Bool, _ detail: String = "") {
            print("\(ok ? "ok  " : "FEHL") \(label)\(detail.isEmpty ? "" : "  — \(detail)")")
            if !ok { failures += 1 }
        }

        check("gs gefunden", Ghostscript.executableURL != nil,
              Ghostscript.executableURL?.path ?? "")

        // Sprachen: der Compiler erzwingt Vollständigkeit, nicht aber Inhalt.
        var langIssues: [String] = []
        for id in PresetID.allCases {
            for (name, t) in [("de", Strings.de), ("en", Strings.en)] {
                if t.presetLabel(id).isEmpty { langIssues.append("\(name): Label \(id.rawValue) leer") }
                if t.presetHint(id).isEmpty  { langIssues.append("\(name): Hinweis \(id.rawValue) leer") }
            }
            if Strings.de.presetLabel(id) == Strings.en.presetLabel(id) && id != .balanced {
                langIssues.append("Label \(id.rawValue) in beiden Sprachen gleich")
            }
        }
        for t in [Strings.de, Strings.en] {
            if t.subtitle.isEmpty || t.dropFirst.isEmpty || t.close.isEmpty {
                langIssues.append("\(t.lang.rawValue): Pflichttext leer")
            }
            for f: Failure in [.ghostscriptMissing, .cancelled, .noAccess, .passwordProtected,
                               .notReadablePDF, .noOutput, .gsFailed(code: 1, detail: ""),
                               .saveFailed("x")] where t.failure(f).isEmpty {
                langIssues.append("\(t.lang.rawValue): Fehlertext leer")
            }
        }
        check("Sprachtabellen vollständig", langIssues.isEmpty, langIssues.joined(separator: "; "))

        // Größenangaben folgen der Sprache
        check("Zahlformat je Sprache",
              Strings.de.bytes(14_500_000).contains(",") && Strings.en.bytes(14_500_000).contains("."),
              "de=\(Strings.de.bytes(14_500_000))  en=\(Strings.en.bytes(14_500_000))")

        // QFactor: muss monoton fallen, wenn die Qualität steigt
        let qs = [10, 35, 55, 72, 85, 98]
        let fs = qs.map { Ghostscript.qFactor(for: $0) }
        check("QFactor fällt monoton", zip(fs, fs.dropFirst()).allSatisfy { $0 > $1 },
              fs.map { String(format: "%.2f", $0) }.joined(separator: " > "))

        // JPEGQ darf nicht vorkommen (pdfwrite ignoriert es), QFactor muss drin sein
        var s = Settings(); s.apply(Preset.named(.strong))
        let args = Ghostscript.arguments(settings: s, input: input,
                                         output: URL(fileURLWithPath: "/tmp/o.pdf"))
        check("kein -dJPEGQ", !args.contains { $0.contains("JPEGQ") })
        check("QFactor gesetzt", args.contains { $0.contains("/QFactor") })
        check("-c kommt nach -sOutputFile",
              args.firstIndex(of: "-c")! > args.firstIndex { $0.hasPrefix("-sOutputFile") }!)
        check("Eingabe steht am Ende", args.last == input.path)

        // "Nur optimieren" darf keine Bildfilter erzwingen
        var o = Settings(); o.apply(Preset.named(.optimize))
        let oargs = Ghostscript.arguments(settings: o, input: input,
                                          output: URL(fileURLWithPath: "/tmp/o.pdf"))
        check("optimize ohne QFactor", !oargs.contains { $0.contains("/QFactor") })
        check("optimize reicht JPEG durch", oargs.contains("-dPassThroughJPEGImages=true"))

        // Echter Lauf über alle Stufen
        let before = fileSize(input)
        for preset in Preset.all {
            var st = Settings(); st.apply(preset)
            let out = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("st-\(preset.id.rawValue).pdf")
            let run = GSRun()
            let pages = Counter(), lastPage = Counter()
            do {
                let t0 = Date()
                try await run.run(settings: st, input: input, output: out,
                                  onTotal: { pages.set($0) }, onPage: { lastPage.set($0) })
                let after = fileSize(out)
                let pct = Int((1 - Double(after) / Double(before)) * 100)
                check("Stufe \(preset.id.rawValue)", after > 0,
                      "\(before/1024) KB → \(after/1024) KB (−\(pct)%), "
                      + "\(lastPage.value)/\(pages.value) Seiten, "
                      + String(format: "%.2fs", Date().timeIntervalSince(t0)))
                if lastPage.value != pages.value || pages.value == 0 {
                    check("  Fortschritt vollständig", false,
                          "Seite \(lastPage.value) von \(pages.value)")
                }
            } catch {
                check("Stufe \(preset.id.rawValue)", false, Strings.de.failure(error as? Failure ?? .cancelled))
            }
        }

        // Abbruch muss greifen
        var c = Settings(); c.apply(Preset.named(.light))
        let cancelRun = GSRun()
        let cout = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("cancel.pdf")
        Task { try? await Task.sleep(nanoseconds: 30_000_000); cancelRun.cancel() }
        do {
            try await cancelRun.run(settings: c, input: input, output: cout,
                                    onTotal: { _ in }, onPage: { _ in })
            check("Abbruch", false, "lief komplett durch (Datei evtl. zu klein zum Abbrechen)")
        } catch {
            check("Abbruch", true, Strings.de.failure(error as? Failure ?? .cancelled))
        }

        // Fehlerfall: kaputte Datei
        let bad = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("bad.pdf")
        try? "kein pdf".data(using: .utf8)!.write(to: bad)
        do {
            try await GSRun().run(settings: s, input: bad,
                                  output: URL(fileURLWithPath: NSTemporaryDirectory() + "/x.pdf"),
                                  onTotal: { _ in }, onPage: { _ in })
            check("defekte Datei meldet Fehler", false, "kein Fehler geworfen")
        } catch {
            check("defekte Datei meldet Fehler", true,
                  String(Strings.de.failure(error as? Failure ?? .cancelled).prefix(70)))
        }

        print(failures == 0 ? "\nalle Prüfungen bestanden" : "\n\(failures) Prüfung(en) fehlgeschlagen")
        exit(failures == 0 ? 0 : 1)
    }

    static func fileSize(_ url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int64) ?? 0
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var v = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return v }
    func set(_ n: Int) { lock.lock(); v = n; lock.unlock() }
}
