import SwiftUI
import PDFKit

/// Seite vorher/nachher nebeneinander — zum Prüfen, ob die Stufe passt.
struct CompareView: View {
    let item: FileItem
    @EnvironmentObject var store: Store
    private var s: Strings { store.s }
    @Environment(\.dismiss) private var dismiss
    @State private var page = 1
    @State private var before: NSImage?
    @State private var after: NSImage?

    private var pageCount: Int { max(item.pages, 1) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(item.name).font(.system(size: 13, weight: .semibold))
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Button { step(-1) } label: { Image(systemName: "chevron.left") }
                    .disabled(page <= 1)
                Text(s.pageOf(page, pageCount))
                    .font(.system(size: 11)).monospacedDigit()
                Button { step(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(page >= pageCount)
                Button(s.close) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(12)
            Divider()

            HStack(spacing: 12) {
                pane(s.original, s.bytes(item.originalSize), before)
                pane(s.compressed, s.bytes(item.newSize), after)
            }
            .padding(12)
        }
        .frame(width: 900, height: 660)
        .task(id: page) { await render() }
    }

    private func pane(_ title: String, _ size: String, _ image: NSImage?) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(title).font(.system(size: 11, weight: .medium))
                Spacer()
                Text(size).font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
            }
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05))
                if let image {
                    Image(nsImage: image).resizable().scaledToFit().padding(4)
                } else {
                    ProgressView()
                }
            }
        }
    }

    private func step(_ d: Int) {
        page = min(max(1, page + d), pageCount)
    }

    private func render() async {
        let target = page
        let originalURL = item.url
        let outputURL = item.outputURL
        // PDFKit rastert beide Seiten gleich groß — nur so sind sie vergleichbar.
        let size = NSSize(width: 1000, height: 1400)
        let a = await Task.detached { thumbnail(originalURL, target, size) }.value
        let b = outputURL == nil ? nil
              : await Task.detached { thumbnail(outputURL!, target, size) }.value
        before = a
        after = b
    }
}

private func thumbnail(_ url: URL, _ page: Int, _ size: NSSize) -> NSImage? {
    guard let doc = PDFDocument(url: url),
          page >= 1, page <= doc.pageCount,
          let p = doc.page(at: page - 1) else { return nil }
    return p.thumbnail(of: size, for: .cropBox)
}
