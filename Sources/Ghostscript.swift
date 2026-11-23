import Foundation

enum GSError: LocalizedError {
    case notInstalled
    case failed(code: Int32, detail: String)
    case cancelled
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "Ghostscript wurde nicht gefunden. Im Terminal installieren: brew install ghostscript"
        case .failed(let code, let detail):
            return detail.isEmpty ? "Ghostscript-Fehler (Code \(code))"
                                  : "Ghostscript-Fehler (Code \(code)): \(detail)"
        case .cancelled:
            return "Abgebrochen"
        case .unreadable(let why):
            return why
        }
    }
}

enum Ghostscript {

    /// Pfad zum gs-Binary. Eine GUI-App erbt die PATH-Variable der Shell nicht,
    /// deshalb werden die üblichen Orte direkt geprüft.
    static let executableURL: URL? = {
        var candidates = ["/opt/homebrew/bin/gs", "/usr/local/bin/gs", "/usr/bin/gs"]
        if let env = ProcessInfo.processInfo.environment["PATH"] {
            candidates += env.split(separator: ":").map { "\($0)/gs" }
        }
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }()

    static var version: String {
        guard let url = executableURL else { return "fehlt" }
        let p = Process()
        p.executableURL = url
        p.arguments = ["--version"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return "?" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "?"
    }

    // MARK: - Qualität

    /// JPEG-Qualität (1…100) → Distiller-QFactor. pdfwrite kennt kein -dJPEGQ
    /// (das gilt nur für JPEG-Ausgabegeräte); die Bildqualität läuft über
    /// setdistillerparams. Ankerpunkte wie bei Distiller:
    /// Maximum 0.1 / Hoch 0.4 / Mittel 0.76 / Niedrig 1.3 / Minimum 2.4.
    static func qFactor(for quality: Int) -> Double {
        let table: [(q: Double, f: Double)] = [
            (100, 0.05), (95, 0.10), (90, 0.20), (80, 0.40), (70, 0.55),
            (60, 0.76), (50, 1.00), (40, 1.30), (30, 1.80), (20, 2.40), (1, 4.50),
        ]
        let q = Double(min(100, max(1, quality)))
        for i in 0..<(table.count - 1) {
            let hi = table[i], lo = table[i + 1]
            if q <= hi.q && q >= lo.q {
                let t = (hi.q - q) / (hi.q - lo.q)
                return ((hi.f + t * (lo.f - hi.f)) * 1000).rounded() / 1000
            }
        }
        return 0.76
    }

    // MARK: - Aufruf

    static func arguments(settings: Settings, input: URL, output: URL) -> [String] {
        var args = [
            "-sDEVICE=pdfwrite",
            "-dCompatibilityLevel=\(settings.pdfVersion)",
            "-dNOPAUSE", "-dBATCH", "-dSAFER",
            // Struktur-Optimierungen, die nie Qualität kosten
            "-dDetectDuplicateImages=true",
            "-dCompressFonts=true", "-dSubsetFonts=true",
            "-dCompressPages=true",
        ]

        if settings.mode == .optimize {
            // Bilddaten unangetastet lassen, nur die PDF-Struktur neu schreiben.
            args += [
                "-dPassThroughJPEGImages=true", "-dPassThroughJPXImages=true",
                "-dDownsampleColorImages=false", "-dDownsampleGrayImages=false",
                "-dDownsampleMonoImages=false",
                "-dAutoFilterColorImages=true", "-dAutoFilterGrayImages=true",
            ]
        } else {
            args += [
                "-dDownsampleColorImages=true", "-dColorImageDownsampleType=/Bicubic",
                "-dColorImageResolution=\(settings.dpi)",
                "-dDownsampleGrayImages=true", "-dGrayImageDownsampleType=/Bicubic",
                "-dGrayImageResolution=\(settings.dpi)",
                "-dDownsampleMonoImages=true", "-dMonoImageDownsampleType=/Subsample",
                "-dMonoImageResolution=\(settings.monoDPI)",
                "-dAutoFilterColorImages=false", "-dColorImageFilter=/DCTEncode",
                "-dAutoFilterGrayImages=false", "-dGrayImageFilter=/DCTEncode",
                "-dPassThroughJPEGImages=false", "-dPassThroughJPXImages=false",
                // Erst ab dem 1,2-fachen Zielwert herunterrechnen, sonst matscht es grundlos
                "-dColorImageDownsampleThreshold=1.2",
                "-dGrayImageDownsampleThreshold=1.2",
                "-dMonoImageDownsampleThreshold=1.2",
            ]
        }

        if settings.grayscale {
            args += ["-sColorConversionStrategy=Gray", "-dProcessColorModel=/DeviceGray"]
        }
        if settings.stripMetadata {
            args += ["-dOmitInfoDate=true", "-dOmitXMP=true", "-dOmitID=true"]
        }
        if settings.fastWeb {
            args += ["-dFastWebView=true"]
        }

        args.append("-sOutputFile=\(output.path)")

        if settings.mode != .optimize {
            let qf = qFactor(for: settings.quality)
            // Unter ~75 lohnt Chroma-Subsampling, darüber kostet es sichtbar Qualität.
            let samp = settings.quality >= 75 ? "[1 1 1 1]" : "[2 1 1 2]"
            let dict = "<< /QFactor \(qf) /Blend 1 /HSamples \(samp) /VSamples \(samp) >>"
            args += ["-c", "<< /ColorImageDict \(dict) /ColorACSImageDict \(dict) "
                         + "/GrayImageDict \(dict) /GrayACSImageDict \(dict) >> setdistillerparams",
                     "-f"]
        }

        args.append(input.path)
        return args
    }
}
