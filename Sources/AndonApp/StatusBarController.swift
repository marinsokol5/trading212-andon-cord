import AppKit
import Observation
import SwiftUI
import Trading212Core

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate, NSPopoverDelegate {
    private let model: AppModel
    private let openApp: () -> Void
    private let openSettings: () -> Void
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let contextMenu = NSMenu()

    init(model: AppModel, openApp: @escaping () -> Void, openSettings: @escaping () -> Void) {
        self.model = model
        self.openApp = openApp
        self.openSettings = openSettings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        statusItem.autosaveName = "\(AppVariant.current.bundleIdentifier).status"
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
        }

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: PortfolioPopoverView(
            model: model,
            openApp: { [weak self] in self?.closeAndOpenApp() },
            openSettings: { [weak self] in self?.closeAndOpenSettings() }))

        contextMenu.delegate = self
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
            Task { @MainActor in self?.observe() }
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
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func showContextMenu() {
        guard let button = statusItem.button else { return }
        menuNeedsUpdate(contextMenu)
        contextMenu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: button.bounds.minY - 2),
            in: button)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if let snapshot = model.displaySnapshot {
            addInfo(
                model.isPrivate
                    ? "Portfolio value hidden"
                    : model.privateAmount(snapshot.totalValue, currency: snapshot.currencyCode, style: .fullWithCents),
                to: menu)
            addInfo("Updated \(snapshot.asOf.formatted(date: .omitted, time: .shortened))", to: menu, caption: true)
        } else {
            addInfo(model.hasReadCredential ? "Portfolio unavailable" : "Viewing key not configured", to: menu)
        }
        if let error = model.errorMessage { addInfo(error, to: menu, caption: true) }

        menu.addItem(.separator())
        addAction("Open Trading212 Andon Cord", selector: #selector(openAppAction), key: "o", to: menu)
        addAction("Refresh Now", selector: #selector(refreshAction), key: "r", to: menu,
                  enabled: model.hasReadCredential && !model.isRefreshing)
        addAction(
            model.isPrivate ? "Show Portfolio Values" : "Hide Portfolio Values",
            selector: #selector(togglePrivacyAction),
            key: "h",
            to: menu,
            image: symbol(model.isPrivate ? "eye" : "eye.slash"))
        menu.addItem(.separator())
        addAction("Settings…", selector: #selector(openSettingsAction), key: ",", to: menu)
        addAction("Quit Trading212 Andon Cord", selector: #selector(quitAction), key: "q", to: menu)
    }

    private func addInfo(_ title: String, to menu: NSMenu, caption: Bool = false) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        if caption {
            item.attributedTitle = NSAttributedString(string: title, attributes: [
                .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
            ])
        }
        menu.addItem(item)
    }

    private func addAction(
        _ title: String,
        selector: Selector,
        key: String,
        to menu: NSMenu,
        enabled: Bool = true,
        image: NSImage? = nil
    ) {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        item.keyEquivalentModifierMask = .command
        item.isEnabled = enabled
        item.image = image
        menu.addItem(item)
    }

    private func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }

    private func closeAndOpenApp() { popover.performClose(nil); openApp() }
    private func closeAndOpenSettings() { popover.performClose(nil); openSettings() }

    @objc private func openAppAction() { closeAndOpenApp() }
    @objc private func openSettingsAction() { closeAndOpenSettings() }
    @objc private func refreshAction() { Task { await model.refresh() } }
    @objc private func togglePrivacyAction() { model.togglePrivacy() }
    @objc private func quitAction() { NSApp.terminate(nil) }
}
