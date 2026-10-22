import AppKit
import Sparkle
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
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesButton(updater: delegate.updater.updater, model: delegate.model)
            }
        }
    }
}

/// Пункт меню «Перевірити оновлення…» (неактивний, поки перевірка вже йде).
private struct CheckForUpdatesButton: View {
    let updater: SPUUpdater
    let model: SorterModel

    var body: some View {
        Button(model.t("Перевірити оновлення…", "Check for Updates…")) {
            updater.checkForUpdates()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = SorterModel()
    /// Sparkle: раз на день перевіряє appcast.xml з GitHub Releases і пропонує оновитися.
    let updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

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
