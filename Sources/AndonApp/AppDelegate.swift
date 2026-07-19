import AppKit
import Trading212Core

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    private var mainWindowController: MainWindowController?
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        ApplicationMenu.install(appDelegate: self)

        let main = MainWindowController(model: model)
        mainWindowController = main

        statusBarController = StatusBarController(
            model: model,
            openApp: { [weak main] in main?.show() },
            openSettings: { [weak main] in main?.show(route: .settings) })

        main.show()
        Task { await model.start() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag { mainWindowController?.show() }
        return true
    }

    @objc func showSettingsAction() { mainWindowController?.show(route: .settings) }
    @objc func refreshAction() { Task { await model.refresh() } }
    @objc func togglePrivacyAction() { model.togglePrivacy() }
}
