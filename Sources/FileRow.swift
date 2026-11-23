import SwiftUI
import AppKit

struct FileRow: View {
    @ObservedObject var item: FileItem
    @EnvironmentObject var store: Store
    private var s: Strings { store.s }
    let compare: (FileItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(item.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                if case .done = item.state {
                    Text(s.percent(item.savedFraction))
                        .font(.system(size: 12.5, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(item.savedFraction >= 0.1 ? Color.green : Color.orange)
                }
                Button {
                    store.remove(item)
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help(s.removeFromList)
            }

            ProgressView(value: item.progress)
                .progressViewStyle(.linear)
                .tint(tint)

            Text(status).font(.system(size: 11)).monospacedDigit()
                .foregroundStyle(isError ? Color.red : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if item.usedOriginal {
                Text(s.grewWarning)
                    .font(.system(size: 11)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let saved = item.savedURL {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(s.savedAs(saved.path)).lineLimit(1).truncationMode(.middle)
                    Button(s.showInFinder) {
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
                Button(s.saveNextToOriginal) { store.saveNextToOriginal(item) }
                    .disabled(item.savedURL != nil)
                Button(s.saveAs) { saveAs() }
                Button(s.compareQuality) { compare(item) }
                Button(s.recompress) { store.enqueue(item) }
            }
            .controlSize(.small)
        case .failed:
            HStack(spacing: 7) {
                Button(s.retry) { store.enqueue(item) }
                Button(s.showInFinder) {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                }
            }
            .controlSize(.small)
        case .running, .queued:
            Button(s.cancel) { item.run?.cancel() }
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
            return s.queued(s.bytes(item.originalSize))
        case .running:
            return item.pages > 0
                ? s.compressingPage(max(item.page, 1), item.pages)
                : s.analyzing
        case .done:
            let saved = item.originalSize - (item.newSize ?? item.originalSize)
            let before = s.bytes(item.originalSize)
            let after = s.bytes(item.newSize)
            return saved > 0 ? s.resultLine(before, after, s.bytes(saved))
                             : s.resultNoGain(before, after)
        case .failed(let failure):
            return s.failure(failure)
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
