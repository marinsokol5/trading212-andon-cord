import AppKit
import SwiftUI
import Trading212Core

@MainActor
final class MainWindowController: NSWindowController {
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
        let hosting = NSHostingController(rootView: RootView(model: model))
        let window = NSWindow(contentViewController: hosting)
        window.title = AppVariant.current.appName
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 1150, height: 740))
        window.contentMinSize = NSSize(width: 940, height: 620)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.center()
        super.init(window: window)
        shouldCascadeWindows = false
    }

    required init?(coder: NSCoder) { nil }

    func show(route: AppRoute? = nil) {
        if let route { model.navigate(to: route) }
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
