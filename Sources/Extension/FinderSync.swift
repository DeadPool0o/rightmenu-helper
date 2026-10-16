import AppKit
import FinderSync

@objc(RightClickFinderSync)
final class RightClickFinderSync: FIFinderSync {
    private var menuContext: Selection?
    private var backgroundContext = false
    private var configuration = AssistantConfiguration()
    private var optionsByTag: [Int: ActionOptions] = [:]
    private var nextTag = 1000

    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/", isDirectory: true)]
        ActionLog.record("extension ready " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""))
    }
    override var toolbarItemName: String { "右键助手" }
    override var toolbarItemToolTip: String { "右键助手" }
    override var toolbarItemImage: NSImage {
        NSImage(systemSymbolName: "cursorarrow.click.2", accessibilityDescription: "右键助手") ?? NSImage()
    }
    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        configuration = AssistantConfiguration.load()
        optionsByTag.removeAll(); nextTag = 1000
        let controller = FIFinderSyncController.default()
        let target = controller.targetedURL()
        let selected: [URL]
        switch menuKind {
        case .contextualMenuForContainer: selected = []
        case .contextualMenuForSidebar: selected = target.map { [$0] } ?? []
        default: selected = controller.selectedItemURLs() ?? []
        }
        backgroundContext = selected.isEmpty
        let inputs = selected.isEmpty ? target.map { [$0] } ?? [] : selected
        menuContext = try? Selection(urls: inputs)
        let available = MenuAction.allCases.filter {
            configuration.enabled($0) && MenuPolicy.allows($0, selected: selected) && ($0 == .settings || menuContext != nil)
        }
        let menu = NSMenu(); menu.autoenablesItems = false
        var creates: [NSMenuItem] = []
        var mainCreates: [NSMenuItem] = []
        if available.contains(.newEmpty) && configuration.customNewFileEnabled {
            let row = item(.newEmpty, title: configuration.customNewFileName, showIcon: configuration.newFileShowIcons)
            if configuration.customNewFileMainMenu { mainCreates.append(row) } else { creates.append(row) }
        }
        if available.contains(.newTemplate) {
            for template in configuration.newFileTemplates where template.enabled {
                let row = item(.newTemplate, title: template.name, options: ActionOptions(template: template.id), showIcon: configuration.newFileShowIcons)
                if configuration.newFileShowIcons {
                    row.image = NSWorkspace.shared.icon(forFileType: URL(fileURLWithPath: template.filename).pathExtension)
                }
                if template.showInMainMenu { mainCreates.append(row) } else { creates.append(row) }
            }
        }
        if !creates.isEmpty { menu.addItem(submenu("新建文件", symbol: "doc.badge.plus", items: creates, showIcon: configuration.newFileShowIcons)) }
        for row in mainCreates { menu.addItem(row) }
        for action in [MenuAction.moveTo, .copyTo] where available.contains(action) {
            var paths = Set<String>()
            var destinations = configuration.destinationFolders
            destinations += configuration.commonFolders.map { FolderReference(name: URL(fileURLWithPath: $0).lastPathComponent, path: $0) }
            var children = destinations.filter { paths.insert($0.path).inserted }.map { folder in
                item(action, title: folder.name, options: ActionOptions(destination: folder.path), symbol: "folder")
            }
            children.append(item(action, title: "自定义路径…"))
            menu.addItem(submenu(action.title, symbol: action.icon, items: children))
        }
        var icons: [NSMenuItem] = []
        if available.contains(.resetIcon) { icons.append(item(.resetIcon, title: "删除自定义图标")) }
        if available.contains(.setIcon) {
            icons += IconPreset.all.map { preset in
                let row = item(.setIcon, title: preset.name, options: ActionOptions(icon: preset.symbol), showIcon: false)
                if configuration.showIcons { row.image = NativeFileIcons.image(for: preset, size: 16) }
                row.isEnabled = NativeFileIcons.image(for: preset) != nil
                return row
            }
            icons.append(item(.setIcon, title: "选择图标图片…"))
        }
        if !icons.isEmpty { menu.addItem(submenu("文件（夹）图标", symbol: "folder.fill", items: icons)) }
        for action in [MenuAction.desktopLink, .airDrop, .share, .copyName, .folderByName, .cut, .paste, .dissolve, .copyPath, .commonFolder, .deleteForever, .unhide, .hide, .hideExtension, .showExtension, .fileInfo, .terminal, .zip, .sevenZip, .encryptedArchive, .extract] where available.contains(action) { menu.addItem(item(action)) }
        if available.contains(.otherApp) {
            var apps = configuration.applications.filter(\.enabled).map { reference -> NSMenuItem in
                let row = item(.otherApp, title: reference.name, options: ActionOptions(application: reference.path))
                row.toolTip = reference.path
                if configuration.showIcons { row.image = NSWorkspace.shared.icon(forFile: reference.path) }; return row
            }
            if !apps.isEmpty { apps.append(.separator()) }
            apps.append(item(.otherApp, title: "添加应用并打开…"))
            menu.addItem(submenu(MenuAction.otherApp.title, symbol: "app", items: apps))
        }
        let conversions = [MenuAction.png, .jpeg, .heic, .webp, .icns, .macIcons, .iosIcons].filter(available.contains)
        if configuration.mergeMenus && !conversions.isEmpty { menu.addItem(submenu("转换图片", symbol: "photo", items: conversions.map { item($0) })) }
        else { for action in conversions { menu.addItem(item(action)) } }
        if available.contains(.wallpaper) { menu.addItem(item(.wallpaper)) }
        menu.addItem(item(.settings))
        return menu
    }
    private func submenu(_ title: String, symbol: String, items: [NSMenuItem], showIcon: Bool? = nil) -> NSMenuItem {
        let row = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title); menu.autoenablesItems = false
        for item in items { menu.addItem(item) }; row.submenu = menu
        if showIcon ?? configuration.showIcons { row.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return row
    }
    private func item(_ action: MenuAction, title: String? = nil, options: ActionOptions? = nil, symbol: String? = nil, showIcon: Bool? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title ?? action.title, action: selector(action), keyEquivalent: "")
        item.target = self; item.tag = action.menuTag
        if let options { item.tag = nextTag; optionsByTag[nextTag] = options; nextTag += 1 }
        item.isEnabled = action == .settings || menuContext != nil
        if showIcon ?? configuration.showIcons { item.image = NSImage(systemSymbolName: symbol ?? action.icon, accessibilityDescription: nil) }
        return item
    }
    private func dispatch(_ action: MenuAction, sender: Any?) {
        let tag = (sender as? NSMenuItem)?.tag ?? 0
        ActionLog.record("menu action=" + action.rawValue + " tag=" + String(tag) + " selectionCount=" + String(menuContext?.urls.count ?? 0) + " background=" + String(backgroundContext))
        let url = Handoff.url(action: action, selection: action == .settings ? nil : menuContext, background: backgroundContext, options: optionsByTag[tag] ?? ActionOptions())
        let host = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let options = NSWorkspace.OpenConfiguration(); options.activates = false
        NSWorkspace.shared.open([url], withApplicationAt: host, configuration: options) { _, error in
            if let error { ActionLog.record("handoff error=" + error.localizedDescription) }
            else { ActionLog.record("handoff delivered action=" + action.rawValue) }
        }
    }
    private func selector(_ action: MenuAction) -> Selector {
        switch action {
        case .otherApp: return #selector(onOtherApp(_:))
        case .terminal: return #selector(onTerminal(_:))
        case .copyPath: return #selector(onCopyPath(_:))
        case .copyName: return #selector(onCopyName(_:))
        case .cut: return #selector(onCut(_:))
        case .paste: return #selector(onPaste(_:))
        case .copyTo: return #selector(onCopyTo(_:))
        case .moveTo: return #selector(onMoveTo(_:))
        case .newText: return #selector(onNewText(_:))
        case .newMarkdown: return #selector(onNewMarkdown(_:))
        case .newTemplate: return #selector(onNewTemplate(_:))
        case .newEmpty: return #selector(onNewEmpty(_:))
        case .commonFolder: return #selector(onCommonFolder(_:))
        case .fileInfo: return #selector(onFileInfo(_:))
        case .folderByName: return #selector(onFolderByName(_:))
        case .dissolve: return #selector(onDissolve(_:))
        case .desktopLink: return #selector(onDesktopLink(_:))
        case .hide: return #selector(onHide(_:))
        case .unhide: return #selector(onUnhide(_:))
        case .hideExtension: return #selector(onHideExtension(_:))
        case .showExtension: return #selector(onShowExtension(_:))
        case .deleteForever: return #selector(onDeleteForever(_:))
        case .zip: return #selector(onZip(_:))
        case .sevenZip: return #selector(onSevenZip(_:))
        case .encryptedArchive: return #selector(onEncryptedArchive(_:))
        case .extract: return #selector(onExtract(_:))
        case .png: return #selector(onPng(_:))
        case .jpeg: return #selector(onJpeg(_:))
        case .heic: return #selector(onHeic(_:))
        case .webp: return #selector(onWebp(_:))
        case .icns: return #selector(onIcns(_:))
        case .macIcons: return #selector(onMacIcons(_:))
        case .iosIcons: return #selector(onIosIcons(_:))
        case .wallpaper: return #selector(onWallpaper(_:))
        case .setIcon: return #selector(onSetIcon(_:))
        case .resetIcon: return #selector(onResetIcon(_:))
        case .airDrop: return #selector(onAirDrop(_:))
        case .share: return #selector(onShare(_:))
        case .qrCode: return #selector(onQrCode(_:))
        case .baiduTranslate: return #selector(onBaiduTranslate(_:))
        case .googleTranslate: return #selector(onGoogleTranslate(_:))
        case .settings: return #selector(onSettings(_:))
        }
    }
    @objc func onOtherApp(_ sender: Any?) { dispatch(.otherApp, sender: sender) }
    @objc func onTerminal(_ sender: Any?) { dispatch(.terminal, sender: sender) }
    @objc func onCopyPath(_ sender: Any?) { dispatch(.copyPath, sender: sender) }
    @objc func onCopyName(_ sender: Any?) { dispatch(.copyName, sender: sender) }
    @objc func onCut(_ sender: Any?) { dispatch(.cut, sender: sender) }
    @objc func onPaste(_ sender: Any?) { dispatch(.paste, sender: sender) }
    @objc func onCopyTo(_ sender: Any?) { dispatch(.copyTo, sender: sender) }
    @objc func onMoveTo(_ sender: Any?) { dispatch(.moveTo, sender: sender) }
    @objc func onNewText(_ sender: Any?) { dispatch(.newText, sender: sender) }
    @objc func onNewMarkdown(_ sender: Any?) { dispatch(.newMarkdown, sender: sender) }
    @objc func onNewTemplate(_ sender: Any?) { dispatch(.newTemplate, sender: sender) }
    @objc func onNewEmpty(_ sender: Any?) { dispatch(.newEmpty, sender: sender) }
    @objc func onCommonFolder(_ sender: Any?) { dispatch(.commonFolder, sender: sender) }
    @objc func onFileInfo(_ sender: Any?) { dispatch(.fileInfo, sender: sender) }
    @objc func onFolderByName(_ sender: Any?) { dispatch(.folderByName, sender: sender) }
    @objc func onDissolve(_ sender: Any?) { dispatch(.dissolve, sender: sender) }
    @objc func onDesktopLink(_ sender: Any?) { dispatch(.desktopLink, sender: sender) }
    @objc func onHide(_ sender: Any?) { dispatch(.hide, sender: sender) }
    @objc func onUnhide(_ sender: Any?) { dispatch(.unhide, sender: sender) }
    @objc func onHideExtension(_ sender: Any?) { dispatch(.hideExtension, sender: sender) }
    @objc func onShowExtension(_ sender: Any?) { dispatch(.showExtension, sender: sender) }
    @objc func onDeleteForever(_ sender: Any?) { dispatch(.deleteForever, sender: sender) }
    @objc func onZip(_ sender: Any?) { dispatch(.zip, sender: sender) }
    @objc func onSevenZip(_ sender: Any?) { dispatch(.sevenZip, sender: sender) }
    @objc func onEncryptedArchive(_ sender: Any?) { dispatch(.encryptedArchive, sender: sender) }
    @objc func onExtract(_ sender: Any?) { dispatch(.extract, sender: sender) }
    @objc func onPng(_ sender: Any?) { dispatch(.png, sender: sender) }
    @objc func onJpeg(_ sender: Any?) { dispatch(.jpeg, sender: sender) }
    @objc func onHeic(_ sender: Any?) { dispatch(.heic, sender: sender) }
    @objc func onWebp(_ sender: Any?) { dispatch(.webp, sender: sender) }
    @objc func onIcns(_ sender: Any?) { dispatch(.icns, sender: sender) }
    @objc func onMacIcons(_ sender: Any?) { dispatch(.macIcons, sender: sender) }
    @objc func onIosIcons(_ sender: Any?) { dispatch(.iosIcons, sender: sender) }
    @objc func onWallpaper(_ sender: Any?) { dispatch(.wallpaper, sender: sender) }
    @objc func onSetIcon(_ sender: Any?) { dispatch(.setIcon, sender: sender) }
    @objc func onResetIcon(_ sender: Any?) { dispatch(.resetIcon, sender: sender) }
    @objc func onAirDrop(_ sender: Any?) { dispatch(.airDrop, sender: sender) }
    @objc func onShare(_ sender: Any?) { dispatch(.share, sender: sender) }
    @objc func onQrCode(_ sender: Any?) { dispatch(.qrCode, sender: sender) }
    @objc func onBaiduTranslate(_ sender: Any?) { dispatch(.baiduTranslate, sender: sender) }
    @objc func onGoogleTranslate(_ sender: Any?) { dispatch(.googleTranslate, sender: sender) }
    @objc func onSettings(_ sender: Any?) { dispatch(.settings, sender: sender) }
}
