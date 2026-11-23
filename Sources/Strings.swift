import Foundation

// MARK: - Sprache

enum Lang: String, CaseIterable, Identifiable {
    case de, en
    var id: String { rawValue }

    var short: String { self == .de ? "DE" : "EN" }
    var strings: Strings { self == .de ? .de : .en }

    /// Zahlen- und Größenformate folgen der gewählten Sprache,
    /// damit nicht "13,8 MB" in einer englischen Oberfläche steht.
    var locale: Locale { Locale(identifier: self == .de ? "de_DE" : "en_US") }

    /// Beim ersten Start der Systemsprache folgen, danach der Wahl des Nutzers.
    static var initial: Lang {
        if let raw = UserDefaults.standard.string(forKey: "language"),
           let saved = Lang(rawValue: raw) { return saved }
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("de") ? .de : .en
    }
}

// MARK: - Fehlerarten
//
// Fehler werden als Fall gespeichert, nicht als fertiger Text: sonst bliebe
// eine Meldung in der Sprache stehen, in der sie entstanden ist.

enum Failure: Error, Equatable {
    case ghostscriptMissing
    case gsFailed(code: Int32, detail: String)
    case cancelled
    case noAccess
    case passwordProtected
    case notReadablePDF
    case noOutput
    case saveFailed(String)
}

// MARK: - Texte
//
// Alle sichtbaren Texte als gespeicherte Felder: fehlt in einer Sprache eines,
// übersetzt der Compiler nicht.

struct Strings {
    let lang: Lang

    // Kopfzeile
    let subtitle: String
    let ghostscriptMissingChip: String
    let gsVersion: (String) -> String

    // Ablagefläche
    let dropFirst: String
    let dropMore: String
    let dropHint: String
    let addFiles: String          // Menüeintrag
    let addPanelPrompt: String    // Knopf im Auswahldialog

    // Einstellungen
    let compressionLevel: String
    let advanced: String
    let autoSave: String
    let imageResolution: String
    let jpegQuality: String
    let monoResolution: String
    let pdfVersion: String
    let grayscale: String
    let stripMetadata: String
    let fastWeb: String
    let advancedNote: String

    // Stufen
    let presetLabel: (PresetID) -> String
    let presetHint: (PresetID) -> String

    // Dateizeile
    let removeFromList: String
    let queued: (String) -> String
    let analyzing: String
    let compressingPage: (Int, Int) -> String
    let resultLine: (String, String, String) -> String   // vorher, nachher, gespart
    let resultNoGain: (String, String) -> String
    let grewWarning: String
    let savedAs: (String) -> String
    let showInFinder: String
    let saveNextToOriginal: String
    let saveAs: String
    let compareQuality: String
    let recompress: String
    let retry: String
    let cancel: String

    // Fußzeile
    let saveAllNextToOriginals: String
    let recompressAll: String
    let clearList: String
    let totals: (Int, String, String, String) -> String

    // Vergleich
    let original: String
    let compressed: String
    let pageOf: (Int, Int) -> String
    let close: String

    // Ghostscript-Hinweis
    let gsAlertTitle: String
    let gsAlertBody: String

    // Fehlermeldungen
    let failure: (Failure) -> String

    // MARK: Formate

    func bytes(_ n: Int64?) -> String {
        guard let n else { return "–" }
        // Dezimal, nicht binär: der Finder zählt seit macOS 10.6 so, und eine
        // Datei soll in beiden Programmen dieselbe Größe haben.
        let units = ["B", "KB", "MB", "GB"]
        var value = Double(n)
        var unit = 0
        while value >= 1000, unit < units.count - 1 { value /= 1000; unit += 1 }
        let nf = NumberFormatter()
        nf.locale = lang.locale
        // Bytes und KB ohne Nachkommastelle, ab MB mit einer - wie gewohnt
        let decimals = unit >= 2 ? 1 : 0
        nf.minimumFractionDigits = decimals
        nf.maximumFractionDigits = decimals
        let num = nf.string(from: NSNumber(value: value)) ?? "\(Int(value))"
        return "\(num) \(units[unit])"
    }

    func percent(_ fraction: Double) -> String {
        let p = Int((abs(fraction) * 100).rounded())
        if p == 0 { return "±0 %" }
        return (fraction >= 0 ? "−" : "+") + "\(p) %"
    }
}

// MARK: - Deutsch

extension Strings {
    static let de = Strings(
        lang: .de,
        subtitle: "PDFs verkleinern — reinziehen, Stufe wählen, fertig",
        ghostscriptMissingChip: "Ghostscript fehlt",
        gsVersion: { "Ghostscript \($0)" },

        dropFirst: "PDFs hierher ziehen",
        dropMore: "Weitere PDFs hierher ziehen",
        dropHint: "oder klicken, um Dateien zu wählen · mehrere gleichzeitig möglich",
        addFiles: "PDFs hinzufügen …",
        addPanelPrompt: "Hinzufügen",

        compressionLevel: "KOMPRESSIONSSTUFE",
        advanced: "Erweiterte Einstellungen",
        autoSave: "Ergebnis sofort neben dem Original speichern",
        imageResolution: "Bildauflösung (Farbe / Graustufen)",
        jpegQuality: "JPEG-Qualität",
        monoResolution: "Auflösung Schwarz-Weiß-Bilder",
        pdfVersion: "PDF-Version",
        grayscale: "Graustufen",
        stripMetadata: "Metadaten entfernen",
        fastWeb: "Für Web optimieren",
        advancedNote: "Bei „Nur optimieren“ bleiben Bilder unangetastet — Auflösung und "
            + "JPEG-Qualität werden dann ignoriert. „Für Web optimieren“ erlaubt keine "
            + "Objekt-Streams und kann die Datei leicht vergrößern.",

        presetLabel: { id in
            switch id {
            case .extreme:  return "Maximal"
            case .strong:   return "Stark"
            case .balanced: return "Ausgewogen"
            case .light:    return "Leicht"
            case .optimize: return "Nur optimieren"
            }
        },
        presetHint: { id in
            switch id {
            case .extreme:  return "72 dpi · kleinste Datei"
            case .strong:   return "110 dpi · E-Mail"
            case .balanced: return "150 dpi · Standard"
            case .light:    return "225 dpi · Bürodruck"
            case .optimize: return "Bilder unverändert"
            }
        },

        removeFromList: "Aus der Liste entfernen",
        queued: { "In Warteschlange · \($0)" },
        analyzing: "Analysiere Dokument …",
        compressingPage: { page, total in "Komprimiere Seite \(page) von \(total) …" },
        resultLine: { before, after, saved in "\(before) → \(after)  ·  \(saved) gespart" },
        resultNoGain: { before, after in "\(before) → \(after)  ·  keine Ersparnis" },
        grewWarning: "Neu geschrieben wäre die Datei größer geworden — du bekommst das "
            + "unveränderte Original. Mit einer stärkeren Stufe lässt sich meist noch sparen.",
        savedAs: { "Gespeichert: \($0)" },
        showInFinder: "Im Finder zeigen",
        saveNextToOriginal: "Neben Original speichern",
        saveAs: "Speichern unter …",
        compareQuality: "Qualität vergleichen",
        recompress: "Neu komprimieren",
        retry: "Erneut versuchen",
        cancel: "Abbrechen",

        saveAllNextToOriginals: "Alle neben Originalen speichern",
        recompressAll: "Mit neuen Einstellungen erneut",
        clearList: "Liste leeren",
        totals: { count, before, after, pct in
            "\(count) fertig · \(before) → \(after) (\(pct))"
        },

        original: "Original",
        compressed: "Komprimiert",
        pageOf: { page, total in "Seite \(page) / \(total)" },
        close: "Schließen",

        gsAlertTitle: "Ghostscript fehlt",
        gsAlertBody: "PDF Shrink nutzt Ghostscript zum Komprimieren.\n\n"
            + "Im Terminal installieren:\n\nbrew install ghostscript",

        failure: { f in
            switch f {
            case .ghostscriptMissing:
                return "Ghostscript wurde nicht gefunden. Im Terminal installieren: "
                     + "brew install ghostscript"
            case .gsFailed(let code, let detail):
                return detail.isEmpty ? "Ghostscript-Fehler (Code \(code))"
                                      : "Ghostscript-Fehler (Code \(code)): \(detail)"
            case .cancelled:
                return "Abgebrochen"
            case .noAccess:
                return "macOS verweigert den Zugriff auf diese Datei. Erlaube den Zugriff "
                     + "unter Systemeinstellungen → Datenschutz & Sicherheit → Dateien und Ordner."
            case .passwordProtected:
                return "Die Datei ist passwortgeschützt und kann nicht verarbeitet werden."
            case .notReadablePDF:
                return "Die Datei konnte nicht als PDF gelesen werden."
            case .noOutput:
                return "Ghostscript hat keine Ausgabedatei erzeugt."
            case .saveFailed(let why):
                return "Speichern fehlgeschlagen: \(why)"
            }
        }
    )
}

// MARK: - Englisch

extension Strings {
    static let en = Strings(
        lang: .en,
        subtitle: "Shrink PDFs — drop them in, pick a level, done",
        ghostscriptMissingChip: "Ghostscript missing",
        gsVersion: { "Ghostscript \($0)" },

        dropFirst: "Drop PDFs here",
        dropMore: "Drop more PDFs here",
        dropHint: "or click to choose files · several at once is fine",
        addFiles: "Add PDFs…",
        addPanelPrompt: "Add",

        compressionLevel: "COMPRESSION LEVEL",
        advanced: "Advanced settings",
        autoSave: "Save result next to the original right away",
        imageResolution: "Image resolution (colour / greyscale)",
        jpegQuality: "JPEG quality",
        monoResolution: "Resolution for black-and-white images",
        pdfVersion: "PDF version",
        grayscale: "Greyscale",
        stripMetadata: "Remove metadata",
        fastWeb: "Optimise for web",
        advancedNote: "With “Optimise only” images are left untouched — resolution and JPEG "
            + "quality are ignored. “Optimise for web” disallows object streams and can make "
            + "the file slightly larger.",

        presetLabel: { id in
            switch id {
            case .extreme:  return "Maximum"
            case .strong:   return "Strong"
            case .balanced: return "Balanced"
            case .light:    return "Light"
            case .optimize: return "Optimise only"
            }
        },
        presetHint: { id in
            switch id {
            case .extreme:  return "72 dpi · smallest file"
            case .strong:   return "110 dpi · email"
            case .balanced: return "150 dpi · standard"
            case .light:    return "225 dpi · office printing"
            case .optimize: return "images unchanged"
            }
        },

        removeFromList: "Remove from list",
        queued: { "Queued · \($0)" },
        analyzing: "Analysing document…",
        compressingPage: { page, total in "Compressing page \(page) of \(total)…" },
        resultLine: { before, after, saved in "\(before) → \(after)  ·  \(saved) saved" },
        resultNoGain: { before, after in "\(before) → \(after)  ·  no saving" },
        grewWarning: "Rewriting would have made this file larger — you get the untouched "
            + "original. A stronger level usually still saves something.",
        savedAs: { "Saved: \($0)" },
        showInFinder: "Show in Finder",
        saveNextToOriginal: "Save next to original",
        saveAs: "Save as…",
        compareQuality: "Compare quality",
        recompress: "Compress again",
        retry: "Try again",
        cancel: "Cancel",

        saveAllNextToOriginals: "Save all next to originals",
        recompressAll: "Run again with new settings",
        clearList: "Clear list",
        totals: { count, before, after, pct in
            "\(count) done · \(before) → \(after) (\(pct))"
        },

        original: "Original",
        compressed: "Compressed",
        pageOf: { page, total in "Page \(page) / \(total)" },
        close: "Close",

        gsAlertTitle: "Ghostscript missing",
        gsAlertBody: "PDF Shrink uses Ghostscript to compress.\n\n"
            + "Install it in Terminal:\n\nbrew install ghostscript",

        failure: { f in
            switch f {
            case .ghostscriptMissing:
                return "Ghostscript was not found. Install it in Terminal: "
                     + "brew install ghostscript"
            case .gsFailed(let code, let detail):
                return detail.isEmpty ? "Ghostscript error (code \(code))"
                                      : "Ghostscript error (code \(code)): \(detail)"
            case .cancelled:
                return "Cancelled"
            case .noAccess:
                return "macOS denies access to this file. Grant access in System Settings → "
                     + "Privacy & Security → Files and Folders."
            case .passwordProtected:
                return "This file is password-protected and cannot be processed."
            case .notReadablePDF:
                return "The file could not be read as a PDF."
            case .noOutput:
                return "Ghostscript produced no output file."
            case .saveFailed(let why):
                return "Saving failed: \(why)"
            }
        }
    )
}
