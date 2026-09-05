import AppKit

/// Builds the application main menu. A menu-bar (`.accessory`) app has no menu
/// bar of its own by default, which means the standard Edit shortcuts
/// (⌘X/⌘C/⌘V/⌘A/⌘Z) are never dispatched down the responder chain — so text
/// fields in the Settings window can't cut/copy/paste/select-all/undo. Installing
/// a real main menu (shown only while one of our windows is active) fixes that.
enum MainMenu {
    /// No default for `onOpenMain`: a call site that omitted it would install
    /// ⌘0 as a menu item that does nothing — the same "a surface that isn't
    /// there" failure the item exists to fix.
    static func build(onOpenMain: @escaping () -> Void) -> NSMenu {
        let mainMenu = NSMenu()

        // App menu. (Localized like everything else — these were the last
        // hardcoded-English menu items in a bilingual app.)
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: L10n.t("menu.about"),
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L10n.t("menu.hide"),
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: L10n.t("menu.hideOthers"),
                                         action: #selector(NSApplication.hideOtherApplications(_:)),
                                         keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: L10n.t("menu.showAll"),
                        action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L10n.t("menu.quitApp"),
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // File menu — Close, so ⌘W works on our windows (without it they are
        // mouse-close only), and the way back to the main window: closing it
        // used to mean the app had no visible surface but the menu bar.
        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: L10n.t("menu.file"))
        fileItem.submenu = fileMenu
        fileMenu.addItem(BlockMenuItem(title: L10n.t("menu.openMain"), keyEquivalent: "0",
                                       handler: onOpenMain))
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: L10n.t("menu.close"),
                         action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        // Edit menu — the whole point of this file.
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: L10n.t("menu.edit"))
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: L10n.t("edit.undo"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: L10n.t("edit.redo"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: L10n.t("edit.cut"), action: Selector(("cut:")), keyEquivalent: "x")
        editMenu.addItem(withTitle: L10n.t("edit.copy"), action: Selector(("copy:")), keyEquivalent: "c")
        editMenu.addItem(withTitle: L10n.t("edit.paste"), action: Selector(("paste:")), keyEquivalent: "v")
        editMenu.addItem(withTitle: L10n.t("edit.delete"), action: Selector(("delete:")), keyEquivalent: "")
        editMenu.addItem(withTitle: L10n.t("edit.selectAll"), action: Selector(("selectAll:")), keyEquivalent: "a")

        return mainMenu
    }
}
