import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @EnvironmentObject var store: Store
    @State private var isTargeted = false
    @State private var showAdvanced = false
    @State private var comparing: FileItem?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    dropZone
                    settingsCard
                    if !store.items.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(store.items) { item in
                                FileRow(item: item, compare: { comparing = $0 })
                            }
                        }
                    }
                }
                .padding(16)
            }
            if !store.finished.isEmpty { Divider(); footer }
        }
        .frame(minWidth: 640, minHeight: 520)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            load(providers)
            return true
        }
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .background(Color.accentColor.opacity(0.08))
                    .allowsHitTesting(false)   // darf niemals Klicks abfangen
                    .ignoresSafeArea()
            }
        }
        .sheet(item: $comparing) { CompareView(item: $0) }
    }

    // MARK: - Kopfzeile

    private var header: some View {
        HStack(spacing: 10) {
            AppMark()
            VStack(alignment: .leading, spacing: 1) {
                Text("PDF Shrink").font(.system(size: 15, weight: .semibold))
                Text("PDFs verkleinern — reinziehen, Stufe wählen, fertig")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Text(Ghostscript.executableURL == nil ? "Ghostscript fehlt"
                                                  : "Ghostscript \(Ghostscript.version)")
                .font(.system(size: 10))
                .foregroundStyle(Ghostscript.executableURL == nil ? .red : .secondary)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }

    // MARK: - Ablagefläche

    private var dropZone: some View {
        Button(action: pickFiles) {
            VStack(spacing: 6) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: store.items.isEmpty ? 26 : 16, weight: .light))
                    .foregroundStyle(.secondary)
                Text(store.items.isEmpty ? "PDFs hierher ziehen" : "Weitere PDFs hierher ziehen")
                    .font(.system(size: store.items.isEmpty ? 14 : 12, weight: .medium))
                if store.items.isEmpty {
                    Text("oder klicken, um Dateien zu wählen · mehrere gleichzeitig möglich")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, store.items.isEmpty ? 30 : 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.primary.opacity(0.03))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .foregroundStyle(Color.secondary.opacity(0.35)))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Einstellungen

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("KOMPRESSIONSSTUFE")
                .font(.system(size: 10, weight: .semibold)).tracking(0.6)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                ForEach(Preset.all) { preset in
                    PresetButton(preset: preset,
                                 selected: store.settings.presetID == preset.id) {
                        store.settings.apply(preset)
                    }
                }
            }

            DisclosureGroup(isExpanded: $showAdvanced) {
                advanced.padding(.top, 10)
            } label: {
                Text("Erweiterte Einstellungen")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }

            Toggle("Ergebnis sofort neben dem Original speichern", isOn: $store.autoSave)
                .font(.system(size: 12))
                .toggleStyle(.checkbox)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
    }

    private var advanced: some View {
        VStack(alignment: .leading, spacing: 12) {
            let editable = store.settings.isCustomisable

            slider("Bildauflösung (Farbe / Graustufen)",
                   value: Binding(get: { Double(store.settings.dpi) },
                                  set: { store.settings.dpi = Int($0) }),
                   range: 36...600, step: 6, suffix: "dpi", enabled: editable)

            slider("JPEG-Qualität",
                   value: Binding(get: { Double(store.settings.quality) },
                                  set: { store.settings.quality = Int($0) }),
                   range: 10...98, step: 1, suffix: "", enabled: editable)

            slider("Auflösung Schwarz-Weiß-Bilder",
                   value: Binding(get: { Double(store.settings.monoDPI) },
                                  set: { store.settings.monoDPI = Int($0) }),
                   range: 150...1800, step: 50, suffix: "dpi", enabled: editable)

            HStack(spacing: 14) {
                Picker("PDF-Version", selection: $store.settings.pdfVersion) {
                    ForEach(Settings.pdfVersions, id: \.self) { Text($0).tag($0) }
                }
                .frame(width: 190)
                Spacer()
            }
            .font(.system(size: 12))

            HStack(spacing: 18) {
                Toggle("Graustufen", isOn: $store.settings.grayscale)
                Toggle("Metadaten entfernen", isOn: $store.settings.stripMetadata)
                Toggle("Für Web optimieren", isOn: $store.settings.fastWeb)
            }
            .font(.system(size: 12))
            .toggleStyle(.checkbox)

            Text("Bei „Nur optimieren“ bleiben Bilder unangetastet — Auflösung und JPEG-Qualität "
               + "werden dann ignoriert. „Für Web optimieren“ erlaubt keine Objekt-Streams und "
               + "kann die Datei leicht vergrößern.")
                .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func slider(_ title: String, value: Binding<Double>,
                        range: ClosedRange<Double>, step: Double,
                        suffix: String, enabled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue))\(suffix.isEmpty ? "" : " " + suffix)")
                    .monospacedDigit().fontWeight(.medium)
            }
            .font(.system(size: 12))
            Slider(value: value, in: range, step: step)
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }

    // MARK: - Fußzeile

    private var footer: some View {
        HStack(spacing: 8) {
            Button("Alle neben Originalen speichern") {
                for item in store.finished where item.savedURL == nil {
                    store.saveNextToOriginal(item)
                }
            }
            .keyboardShortcut("s")

            Button("Mit neuen Einstellungen erneut") { store.recompressAll() }
            Button("Liste leeren") { store.clearFinished() }

            Spacer()

            Text("\(store.finished.count) fertig · \(Fmt.bytes(store.totalBefore)) → "
               + "\(Fmt.bytes(store.totalAfter)) "
               + "(\(Fmt.percent(Fmt.savedFraction(from: store.totalBefore, to: store.totalAfter))))")
                .font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    // MARK: - Dateien einlesen

    private func load(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in store.add(urls: [url]) }
            }
        }
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.pdf]
        panel.prompt = "Hinzufügen"
        if panel.runModal() == .OK { store.add(urls: panel.urls) }
    }
}

// MARK: - Bausteine

/// Das Logo aus der Kopfzeile, gezeichnet statt als Bild geladen.
struct AppMark: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.247, green: 0.369, blue: 0.984),
                                          Color(red: 0.545, green: 0.361, blue: 0.965)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 30, height: 30)
            .overlay(Text("PDF").font(.system(size: 11, weight: .bold)).foregroundStyle(.white))
    }
}

struct PresetButton: View {
    let preset: Preset
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(preset.label).font(.system(size: 12, weight: .semibold))
                Text(preset.hint).font(.system(size: 9.5))
                    .foregroundStyle(selected ? Color.white.opacity(0.85) : Color.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 7)
                .fill(selected ? Color.accentColor : Color.primary.opacity(0.05)))
            .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}
