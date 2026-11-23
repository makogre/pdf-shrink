import SwiftUI
import AppKit

struct FileRow: View {
    @ObservedObject var item: FileItem
    @EnvironmentObject var store: Store
    let compare: (FileItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(item.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                if case .done = item.state {
                    Text(Fmt.percent(item.savedFraction))
                        .font(.system(size: 12.5, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(item.savedFraction >= 0.1 ? Color.green : Color.orange)
                }
                Button {
                    store.remove(item)
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Aus der Liste entfernen")
            }

            ProgressView(value: item.progress)
                .progressViewStyle(.linear)
                .tint(tint)

            Text(status).font(.system(size: 11)).monospacedDigit()
                .foregroundStyle(isError ? Color.red : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if item.usedOriginal {
                Text("Neu geschrieben wäre die Datei größer geworden — du bekommst das "
                   + "unveränderte Original. Mit einer stärkeren Stufe lässt sich meist noch sparen.")
                    .font(.system(size: 11)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let saved = item.savedURL {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Gespeichert: \(saved.path)").lineLimit(1).truncationMode(.middle)
                    Button("Im Finder zeigen") {
                        NSWorkspace.shared.activateFileViewerSelecting([saved])
                    }
                    .buttonStyle(.link)
                }
                .font(.system(size: 11))
            }

            actions
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
    }

    @ViewBuilder private var actions: some View {
        switch item.state {
        case .done:
            HStack(spacing: 7) {
                Button("Neben Original speichern") { store.saveNextToOriginal(item) }
                    .disabled(item.savedURL != nil)
                Button("Speichern unter …") { saveAs() }
                Button("Qualität vergleichen") { compare(item) }
                Button("Neu komprimieren") { store.enqueue(item) }
            }
            .controlSize(.small)
        case .failed:
            HStack(spacing: 7) {
                Button("Erneut versuchen") { store.enqueue(item) }
                Button("Im Finder zeigen") {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                }
            }
            .controlSize(.small)
        case .running, .queued:
            Button("Abbrechen") { item.run?.cancel() }
                .controlSize(.small)
        }
    }

    private var isError: Bool { if case .failed = item.state { return true }; return false }

    private var tint: Color {
        switch item.state {
        case .done:   return .green
        case .failed: return .red
        default:      return .accentColor
        }
    }

    private var status: String {
        switch item.state {
        case .queued:
            return "In Warteschlange · \(Fmt.bytes(item.originalSize))"
        case .running:
            return item.pages > 0
                ? "Komprimiere Seite \(max(item.page, 1)) von \(item.pages) …"
                : "Analysiere Dokument …"
        case .done:
            let saved = item.originalSize - (item.newSize ?? item.originalSize)
            let head = "\(Fmt.bytes(item.originalSize)) → \(Fmt.bytes(item.newSize))"
            return saved > 0 ? head + "  ·  \(Fmt.bytes(saved)) gespart"
                             : head + "  ·  keine Ersparnis"
        case .failed(let msg):
            return msg
        }
    }

    private func saveAs() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = item.suggestedName
        panel.allowedContentTypes = [.pdf]
        panel.directoryURL = item.url.deletingLastPathComponent()
        if panel.runModal() == .OK, let dest = panel.url {
            store.save(item, to: dest)
        }
    }
}
