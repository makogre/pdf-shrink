import Foundation

// MARK: - Kompressionsstufen

/// Eigener Typ statt String: so erzwingt der Compiler, dass jede Stufe in jeder
/// Sprache einen Namen hat.
enum PresetID: String, CaseIterable, Identifiable, Hashable {
    case extreme, strong, balanced, light, optimize
    var id: String { rawValue }
}

struct Preset: Identifiable, Hashable {
    enum Mode: Hashable { case downsample, optimize }

    let id: PresetID
    let mode: Mode
    let dpi: Int
    let quality: Int
    let monoDPI: Int

    static let all: [Preset] = [
        .init(id: .extreme,  mode: .downsample, dpi: 72,  quality: 35, monoDPI: 300),
        .init(id: .strong,   mode: .downsample, dpi: 110, quality: 55, monoDPI: 400),
        .init(id: .balanced, mode: .downsample, dpi: 150, quality: 72, monoDPI: 600),
        .init(id: .light,    mode: .downsample, dpi: 225, quality: 85, monoDPI: 900),
        .init(id: .optimize, mode: .optimize,   dpi: 300, quality: 92, monoDPI: 1200),
    ]

    static func named(_ id: PresetID) -> Preset {
        all.first { $0.id == id } ?? all[2]
    }
}

// MARK: - Einstellungen

struct Settings: Equatable {
    var presetID: PresetID = .balanced
    var dpi = 150
    var quality = 72
    var monoDPI = 600
    var pdfVersion = "1.7"
    var grayscale = false
    var stripMetadata = true
    var fastWeb = false

    var mode: Preset.Mode { Preset.named(presetID).mode }
    var isCustomisable: Bool { mode == .downsample }

    /// Werte der Stufe übernehmen (die Regler folgen der Auswahl).
    mutating func apply(_ preset: Preset) {
        presetID = preset.id
        if preset.mode == .downsample {
            dpi = preset.dpi
            quality = preset.quality
            monoDPI = preset.monoDPI
        }
    }

    static let pdfVersions = ["1.4", "1.5", "1.6", "1.7", "2.0"]
}

// MARK: - Hilfen

enum Fmt {
    /// Ersparnis als Anteil (0…1); negativ, wenn die Datei gewachsen ist.
    static func savedFraction(from: Int64, to: Int64) -> Double {
        guard from > 0 else { return 0 }
        return 1.0 - Double(to) / Double(from)
    }
}
