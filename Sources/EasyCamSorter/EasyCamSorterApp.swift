import AppKit
import SwiftUI

@main
struct EasyCamSorterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Easy CamSorter", id: "main") {
            ContentView()
                .environment(delegate.model)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 860, height: 640)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = SorterModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.refreshCards()
        // Помічаємо, коли картку вставили чи витягли.
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [model] _ in
                MainActor.assumeIsolated { model.refreshCards() }
            }
        }
    }

    /// Папку перетягнули на іконку застосунку в Finder або Dock.
    func application(_ application: NSApplication, open urls: [URL]) {
        if let url = urls.first { model.choose(url) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
