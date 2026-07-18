import AppKit

@MainActor
enum ApplicationMenu {
    static func install(appDelegate: AppDelegate) {
        let main = NSMenu()
        let applicationRoot = NSMenuItem()
        main.addItem(applicationRoot)
        applicationRoot.submenu = applicationMenu(appDelegate: appDelegate)

        let editRoot = NSMenuItem()
        main.addItem(editRoot)
        editRoot.submenu = editMenu()

        let portfolioRoot = NSMenuItem()
        main.addItem(portfolioRoot)
        portfolioRoot.submenu = portfolioMenu(appDelegate: appDelegate)

        let windowRoot = NSMenuItem()
        main.addItem(windowRoot)
        windowRoot.submenu = windowMenu()
        NSApp.mainMenu = main
    }

    private static func applicationMenu(appDelegate: AppDelegate) -> NSMenu {
        let menu = NSMenu(title: "Trading212 Andon Cord")
        menu.addItem(withTitle: "About Trading212 Andon Cord", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        let settings = menu.addItem(
            withTitle: "Settings…",
            action: #selector(AppDelegate.showSettingsAction),
            keyEquivalent: ",")
        settings.target = appDelegate
        menu.addItem(.separator())
        menu.addItem(withTitle: "Hide Trading212 Andon Cord", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = menu.addItem(
            withTitle: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Trading212 Andon Cord", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    /// Cmd+X/C/V/A and undo/redo are key equivalents of Edit-menu items routed
    /// to the first responder; without this menu no text field receives them.
    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = menu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        return menu
    }

    private static func portfolioMenu(appDelegate: AppDelegate) -> NSMenu {
        let menu = NSMenu(title: "Portfolio")
        let refresh = menu.addItem(
            withTitle: "Refresh Now",
            action: #selector(AppDelegate.refreshAction),
            keyEquivalent: "r")
        refresh.target = appDelegate
        let privacy = menu.addItem(
            withTitle: "Toggle Privacy",
            action: #selector(AppDelegate.togglePrivacyAction),
            keyEquivalent: "")
        privacy.target = appDelegate
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        return menu
    }
}
