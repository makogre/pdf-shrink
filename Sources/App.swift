import SwiftUI
import AppKit

@main
struct PDFShrinkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = Store()

    var body: some Scene {
        // Window statt WindowGroup: sonst legt macOS bei jedem Start und jedem
        // Drop aufs Icon ein weiteres, gestaffeltes Fenster an.
        Window("PDF Shrink", id: "main") {
            ContentView()
                .environmentObject(store)
                .onAppear {
                    delegate.store = store
                    delegate.flushPending()
                    warnIfGhostscriptMissing()
                }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 760, height: 620)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .newItem) {
                Button("PDFs hinzufügen …") { delegate.openPanel() }
                    .keyboardShortcut("o")
            }
        }
    }

    private func warnIfGhostscriptMissing() {
        guard Ghostscript.executableURL == nil else { return }
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Ghostscript fehlt"
        alert.informativeText = "PDF Shrink nutzt Ghostscript zum Komprimieren.\n\n"
            + "Im Terminal installieren:\n\nbrew install ghostscript"
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: Store?
    /// Dateien, die beim Start aufs Icon gezogen wurden, bevor das Fenster stand.
    private var pending: [URL] = []

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let store {
            store.add(urls: urls)
        } else {
            pending.append(contentsOf: urls)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor func flushPending() {
        guard let store, !pending.isEmpty else { return }
        store.add(urls: pending)
        pending.removeAll()
    }

    @MainActor func openPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.pdf]
        if panel.runModal() == .OK { store?.add(urls: panel.urls) }
    }
}
