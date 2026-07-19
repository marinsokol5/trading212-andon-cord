import AppKit
import Observation
import SwiftUI
import Trading212Core

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let openApp: () -> Void
    private let openSettings: () -> Void
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var refreshItem: NSMenuItem?
    private var privacyItem: NSMenuItem?

    init(model: AppModel, openApp: @escaping () -> Void, openSettings: @escaping () -> Void) {
        self.model = model
        self.openApp = openApp
        self.openSettings = openSettings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        statusItem.autosaveName = "\(AppVariant.current.bundleIdentifier).status"
        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
        }

        // Explicit isEnabled below; auto-enable would override the manual
        // Refresh-in-flight disabling.
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        observe()
    }

    private func observe() {
        withObservationTracking {
            _ = model.menuBarValue
            _ = model.isPrivate
            _ = model.settings.menuBarLayout
            _ = model.settings.menuBarSymbol
            _ = model.settings.menuBarTint
            render()
        } onChange: { [weak self] in
            // Not a MainActor Task: those queue on the main dispatch queue,
            // which is not drained while menu tracking holds the run loop in
            // .eventTracking — the icon would freeze until the menu closed.
            // A common-modes run loop block executes during tracking too.
            CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
                MainActor.assumeIsolated { self?.observe() }
            }
            CFRunLoopWakeUp(CFRunLoopGetMain())
        }
    }

    private func render() {
        guard let button = statusItem.button else { return }
        let privateMode = model.isPrivate && model.displaySnapshot != nil
        let image = MenuBarRenderer.image(
            value: model.menuBarValue,
            privateMode: privateMode,
            layout: model.settings.menuBarLayout,
            symbol: model.settings.menuBarSymbol,
            tint: model.settings.menuBarTint)
        button.image = image
        button.title = ""
        statusItem.length = image.size.width + 6
        button.setAccessibilityLabel("Trading212 Andon Cord")
        button.setAccessibilityValue(privateMode ? "Portfolio value hidden" : model.menuBarValue)

        // The menu rebuilds on every open; these keep an already-open menu
        // current when privacy toggles via the global shortcut or a refresh
        // lands while it is showing.
        privacyItem?.title = model.isPrivate ? "Show Portfolio Values" : "Hide Portfolio Values"
        privacyItem?.image = NSImage(
            systemSymbolName: model.isPrivate ? "eye" : "eye.slash",
            accessibilityDescription: nil)
        refreshItem?.isEnabled = model.hasReadCredential && !model.isRefreshing
    }

    func menuWillOpen(_ menu: NSMenu) {
        model.pausePrivacyShortcut()
    }

    func menuDidClose(_ menu: NSMenu) {
        model.resumePrivacyShortcut()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let header = NSMenuItem()
        header.isEnabled = false
        let hosting = NSHostingView(rootView: MenuBarHeaderView(model: model))
        hosting.frame.size = hosting.fittingSize
        header.view = hosting
        menu.addItem(header)

        menu.addItem(.separator())
        refreshItem = addAction("Refresh Now", symbol: "arrow.clockwise",
                                selector: #selector(refreshAction), key: "r",
                                enabled: model.hasReadCredential && !model.isRefreshing)
        let privacyKey = model.settings.privacyShortcut.menuKeyEquivalent
        privacyItem = addAction(
            model.isPrivate ? "Show Portfolio Values" : "Hide Portfolio Values",
            symbol: model.isPrivate ? "eye" : "eye.slash",
            selector: #selector(togglePrivacyAction),
            key: privacyKey?.key ?? "",
            mask: privacyKey?.mask ?? [])
        menu.addItem(.separator())
        addAction("Open Trading212 Andon Cord", symbol: "macwindow",
                  selector: #selector(openAppAction), key: "o")
        addAction("Settings…", symbol: "gearshape",
                  selector: #selector(openSettingsAction), key: ",")
        menu.addItem(.separator())
        addAction("Quit Trading212 Andon Cord", symbol: "power",
                  selector: #selector(quitAction), key: "q")
    }

    @discardableResult
    private func addAction(
        _ title: String,
        symbol: String,
        selector: Selector,
        key: String,
        mask: NSEvent.ModifierFlags = .command,
        enabled: Bool = true
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        item.keyEquivalentModifierMask = mask
        item.isEnabled = enabled
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        menu.addItem(item)
        return item
    }

    @objc private func openAppAction() { openApp() }
    @objc private func openSettingsAction() { openSettings() }
    @objc private func refreshAction() { Task { await model.refresh() } }
    @objc private func togglePrivacyAction() { model.togglePrivacy() }
    @objc private func quitAction() { NSApp.terminate(nil) }
}
