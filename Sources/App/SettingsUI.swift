import AppKit
import FinderSync
import ServiceManagement
import UniformTypeIdentifiers

private enum SettingsSection: Int, CaseIterable {
    case general, newFile, destinations, commonFolders, icons, toolbox
    var title: String {
        switch self {
        case .general: return "通用设置"
        case .newFile: return "新建文件"
        case .destinations: return "发送文件到…"
        case .commonFolders: return "常用目录"
        case .icons: return "文件（夹）图标"
        case .toolbox: return "工具箱"
        }
    }
    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .newFile: return "doc.badge.plus"
        case .destinations: return "doc.fill"
        case .commonFolders: return "heart.fill"
        case .icons: return "folder.fill"
        case .toolbox: return "square.grid.2x2.fill"
        }
    }
    var color: NSColor {
        switch self {
        case .general: return .systemBlue
        case .newFile: return .systemTeal
        case .destinations: return .systemGreen
        case .commonFolders: return .systemPink
        case .icons: return .systemOrange
        case .toolbox: return .systemPurple
        }
    }
}

private final class SettingsSidebar: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.24, green: 0.25, blue: 0.26, alpha: 1).setFill()
        bounds.fill()
    }
}

private final class SidebarButton: NSButton {
    var selected = false { didSet { needsDisplay = true } }
    init(section: SettingsSection, target: AnyObject, action: Selector) {
        super.init(frame: .zero)
        title = section.title; tag = section.rawValue; self.target = target; self.action = action
        isBordered = false; bezelStyle = .inline; alignment = .left
        font = .systemFont(ofSize: 15, weight: .medium); contentTintColor = .white
        attributedTitle = NSAttributedString(string: title, attributes: [.font: font!, .foregroundColor: NSColor.white])
        image = SettingsView.tileIcon(section.symbol, color: section.color, size: 27)
        imagePosition = .imageLeading; imageHugsTitle = true
        setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        if selected || isHighlighted {
            NSColor.white.withAlphaComponent(selected ? 0.13 : 0.07).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10).fill()
        }
        image?.draw(in: NSRect(x: 16, y: (bounds.height - 27) / 2, width: 27, height: 27))
        let titleRect = NSRect(x: 57, y: (bounds.height - 20) / 2, width: bounds.width - 67, height: 20)
        attributedTitle.draw(in: titleRect)
        if window?.firstResponder === self {
            NSColor.keyboardFocusIndicatorColor.withAlphaComponent(0.8).setStroke()
            let focus = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 9, yRadius: 9)
            focus.lineWidth = 2; focus.stroke()
        }
    }
}

final class SettingsView: NSView {
    private unowned let app: AppController
    private let content = NSView()
    private var sidebarButtons: [SidebarButton] = []
    private var section: SettingsSection = .newFile
    private var tableController: SettingsTableController?

    init(app: AppController) {
        self.app = app; super.init(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.95, alpha: 1).cgColor
        let sidebar = SettingsSidebar(); sidebar.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sidebar); addSubview(content)
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: leadingAnchor), sidebar.topAnchor.constraint(equalTo: topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: bottomAnchor), sidebar.widthAnchor.constraint(equalToConstant: 218),
            content.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor), content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor), content.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        let logo = NSImageView(); logo.image = Self.tileIcon("cursorarrow.click.2", color: .systemBlue, size: 68)
        logo.translatesAutoresizingMaskIntoConstraints = false; sidebar.addSubview(logo)
        let name = NSTextField(labelWithString: "右键助手")
        name.font = .systemFont(ofSize: 18, weight: .semibold); name.textColor = .white
        name.alignment = .center; name.translatesAutoresizingMaskIntoConstraints = false; sidebar.addSubview(name)
        let version = NSTextField(labelWithString: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
        version.font = .systemFont(ofSize: 11); version.textColor = NSColor.white.withAlphaComponent(0.55)
        version.alignment = .center; version.translatesAutoresizingMaskIntoConstraints = false; sidebar.addSubview(version)
        let stack = NSStackView(); stack.orientation = .vertical; stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false; sidebar.addSubview(stack)
        for page in SettingsSection.allCases {
            let button = SidebarButton(section: page, target: self, action: #selector(selectSection(_:)))
            button.translatesAutoresizingMaskIntoConstraints = false; stack.addArrangedSubview(button)
            button.heightAnchor.constraint(equalToConstant: 44).isActive = true
            button.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            sidebarButtons.append(button)
        }
        NSLayoutConstraint.activate([
            logo.centerXAnchor.constraint(equalTo: sidebar.centerXAnchor), logo.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 64),
            logo.widthAnchor.constraint(equalToConstant: 68), logo.heightAnchor.constraint(equalToConstant: 68),
            name.topAnchor.constraint(equalTo: logo.bottomAnchor, constant: 15), name.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
            name.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12),
            version.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 5), version.centerXAnchor.constraint(equalTo: sidebar.centerXAnchor),
            stack.topAnchor.constraint(equalTo: version.bottomAnchor, constant: 40),
            stack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12), stack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12)
        ])
        showSection(.newFile)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    static func tileIcon(_ symbol: String, color: NSColor, size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        color.setFill(); NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size, height: size), xRadius: size * 0.23, yRadius: size * 0.23).fill()
        if let symbolImage = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size * 0.61, weight: .medium).applying(NSImage.SymbolConfiguration(paletteColors: [.white]))) {
            symbolImage.draw(in: NSRect(x: size * 0.18, y: size * 0.18, width: size * 0.64, height: size * 0.64))
        }
        image.unlockFocus(); image.isTemplate = false; return image
    }
    @objc private func selectSection(_ sender: NSButton) {
        window?.makeFirstResponder(nil)
        if let section = SettingsSection(rawValue: sender.tag) { showSection(section) }
    }
    func refresh() { showSection(section) }
    private func showSection(_ selected: SettingsSection) {
        section = selected
        sidebarButtons.forEach { $0.selected = $0.tag == selected.rawValue }
        content.subviews.forEach { $0.removeFromSuperview() }; tableController = nil
        let heading = NSView()
        heading.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(heading)
        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 30),
            heading.topAnchor.constraint(equalTo: content.topAnchor, constant: 50),
            heading.heightAnchor.constraint(equalToConstant: 0)
        ])
        if selected == .general { buildGeneral(below: heading); return }
        let controller = SettingsTableController(app: app, kind: selected)
        tableController = controller
        let scroll = controller.scrollView; content.addSubview(scroll)
        let toolbar = NSStackView(); toolbar.orientation = .horizontal; toolbar.spacing = 8
        toolbar.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(toolbar)
        let reset = makeButton("重置", action: #selector(resetPage)); content.addSubview(reset)
        let add = makeButton(selected == .newFile ? "添加模板文件…" : selected == .toolbox ? "新建进入 App…" : "+", action: #selector(addEntry))
        let remove = makeButton(selected == .newFile ? "删除" : "−", action: #selector(removeEntry))
        remove.identifier = NSUserInterfaceItemIdentifier("settings-remove-entry")
        controller.selectionChanged = { [weak remove] value in remove?.isEnabled = value }
        remove.isEnabled = false
        if selected != .icons { toolbar.addArrangedSubview(add); toolbar.addArrangedSubview(remove) }
        var options: [NSView] = []
        switch selected {
        case .newFile:
            options = [checkbox("显示图标", value: app.configuration.newFileShowIcons, key: "newFileShowIcons"),
                       checkbox("开启提示音", value: app.configuration.newFileSound, key: "newFileSound"),
                       checkbox("新建文件后自动打开", value: app.configuration.newFileAutoOpen, key: "newFileAutoOpen")]
        case .destinations:
            options = [actionCheckbox(.moveTo, title: "启用移动文件到…"), actionCheckbox(.copyTo, title: "启用复制文件到…")]
        case .commonFolders: options = [actionCheckbox(.commonFolder, title: "启用常用目录")]
        case .icons: options = [actionCheckbox(.setIcon, title: "启用文件（夹）图标"), actionCheckbox(.resetIcon, title: "允许恢复默认图标")]
        case .toolbox:
            options = [checkbox("显示图标", value: app.configuration.showIcons, key: "showIcons"),
                       checkbox("合并显示图片转换菜单", value: app.configuration.mergeMenus, key: "mergeMenus")]
        case .general: break
        }
        let optionGrid = NSGridView(views: stride(from: 0, to: options.count, by: 2).map { index in
            [options[index], index + 1 < options.count ? options[index + 1] : NSView()]
        })
        optionGrid.translatesAutoresizingMaskIntoConstraints = false; optionGrid.rowSpacing = 14; optionGrid.columnSpacing = 32
        content.addSubview(optionGrid)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: heading.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 30),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -30),
            scroll.bottomAnchor.constraint(equalTo: toolbar.topAnchor, constant: -14),
            toolbar.leadingAnchor.constraint(equalTo: scroll.leadingAnchor), toolbar.heightAnchor.constraint(equalToConstant: 28),
            toolbar.bottomAnchor.constraint(equalTo: optionGrid.topAnchor, constant: -22),
            reset.trailingAnchor.constraint(equalTo: scroll.trailingAnchor), reset.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            optionGrid.leadingAnchor.constraint(equalTo: scroll.leadingAnchor), optionGrid.trailingAnchor.constraint(lessThanOrEqualTo: scroll.trailingAnchor),
            optionGrid.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -30)
        ])
    }
    private func buildGeneral(below heading: NSView) {
        let startup = NSButton(checkboxWithTitle: "登录时启动", target: self, action: #selector(toggleLogin(_:)))
        startup.state = SMAppService.mainApp.status == .enabled ? .on : .off
        let cards = NSStackView(views: [startup, checkbox("显示菜单图标", value: app.configuration.showIcons, key: "showIcons"),
                                     makeButton("Finder 扩展设置…", action: #selector(openExtensionSettings))])
        cards.orientation = .vertical; cards.alignment = .leading; cards.spacing = 20
        cards.translatesAutoresizingMaskIntoConstraints = false
        let card = NSView(); card.wantsLayer = true; card.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.72).cgColor
        card.layer?.cornerRadius = 15; card.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(card); card.addSubview(cards)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 20), card.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 30),
            card.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -30),
            cards.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24), cards.topAnchor.constraint(equalTo: card.topAnchor, constant: 24),
            cards.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -24), cards.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -24)
        ])
    }
    private func makeButton(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded; button.controlSize = .regular; button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }
    private func checkbox(_ title: String, value: Bool, key: String) -> NSButton {
        let box = NSButton(checkboxWithTitle: title, target: self, action: #selector(togglePreference(_:)))
        box.state = value ? .on : .off; box.identifier = NSUserInterfaceItemIdentifier(key); return box
    }
    private func actionCheckbox(_ action: MenuAction, title: String? = nil) -> NSButton {
        let box = NSButton(checkboxWithTitle: title ?? action.title, target: self, action: #selector(toggleAction(_:)))
        box.tag = action.menuTag; box.state = app.configuration.enabled(action) ? .on : .off; return box
    }
    @objc private func togglePreference(_ button: NSButton) {
        let enabled = button.state == .on
        switch button.identifier?.rawValue {
        case "newFileShowIcons": app.configuration.newFileShowIcons = enabled
        case "newFileSound": app.configuration.newFileSound = enabled
        case "newFileAutoOpen": app.configuration.newFileAutoOpen = enabled
        case "showIcons": app.configuration.showIcons = enabled
        case "mergeMenus": app.configuration.mergeMenus = enabled
        default: return
        }
        app.persistSettings()
    }
    @objc private func toggleAction(_ button: NSButton) {
        guard let action = MenuAction(menuTag: button.tag) else { return }
        if button.state == .on { app.configuration.disabledActions.remove(action.rawValue) }
        else { app.configuration.disabledActions.insert(action.rawValue) }
        app.persistSettings()
    }
    @objc private func toggleLogin(_ button: NSButton) {
        do {
            if button.state == .on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch { button.state = button.state == .on ? .off : .on; app.error(error) }
    }
    @objc private func openExtensionSettings() { FIFinderSyncController.showExtensionManagementInterface() }
    @objc private func addEntry() {
        switch section {
        case .newFile:
            let panel = NSOpenPanel(); panel.title = "添加模板文件"; panel.canChooseFiles = true
            panel.canChooseDirectories = false; panel.allowsMultipleSelection = true
            guard panel.runModal() == .OK else { return }
            for url in panel.urls {
                guard !app.configuration.newFileTemplates.contains(where: { $0.sourcePath == url.path }) else { continue }
                let id = "custom-" + UUID().uuidString.lowercased()
                let directory = AssistantConfiguration.root.appendingPathComponent("Templates", isDirectory: true)
                    .appendingPathComponent(id, isDirectory: true)
                var reference = TemplateReference(id: id, name: url.deletingPathExtension().lastPathComponent,
                    filename: url.lastPathComponent, sourcePath: url.path, enabled: true, showInMainMenu: false)
                do {
                    let source = try TemplatePolicy.sourceURL(for: reference, resources: Bundle.main.resourceURL ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Resources"))
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let stored = directory.appendingPathComponent(reference.filename)
                    try FileManager.default.copyItem(at: source, to: stored)
                    reference.sourcePath = stored.path
                    app.configuration.newFileTemplates.append(reference)
                } catch {
                    try? FileManager.default.removeItem(at: directory)
                    app.error(error)
                }
            }
        case .destinations, .commonFolders:
            let panel = NSOpenPanel(); panel.title = section == .destinations ? "添加目标目录" : "添加常用目录"
            panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
            guard panel.runModal() == .OK, let url = panel.url else { return }
            if section == .destinations {
                if !app.configuration.destinationFolders.contains(where: { $0.path == url.path }) {
                    app.configuration.destinationFolders.append(FolderReference(name: url.lastPathComponent, path: url.path))
                }
            } else if !app.configuration.commonFolders.contains(url.path) { app.configuration.commonFolders.append(url.path) }
        case .toolbox:
            let panel = NSOpenPanel(); panel.title = "添加右键打开应用"; panel.allowedContentTypes = [.applicationBundle]
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
            guard panel.runModal() == .OK, let url = panel.url else { return }
            app.addApplication(url)
        default: return
        }
        app.persistSettings(); tableController?.reload()
    }
    @objc private func removeEntry() {
        guard let row = tableController?.selectedRow, row >= 0 else { return }
        switch section {
        case .newFile:
            guard row > 0 else { return }
            app.configuration.newFileTemplates.remove(at: row - 1)
        case .destinations: app.configuration.destinationFolders.remove(at: row)
        case .commonFolders: app.configuration.commonFolders.remove(at: row)
        case .toolbox:
            guard let index = tableController?.applicationIndex(forRow: row) else { return }
            app.configuration.applications.remove(at: index)
        default: return
        }
        app.persistSettings(); tableController?.reload()
    }
    @objc private func resetPage() {
        let alert = NSAlert(); alert.messageText = "重置" + section.title + "？"
        alert.informativeText = "恢复这一页的默认设置。"; alert.addButton(withTitle: "取消"); alert.addButton(withTitle: "重置")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        let defaults = AssistantConfiguration()
        switch section {
        case .newFile:
            app.configuration.newFileTemplates = TemplateReference.defaults
            app.configuration.newFileShowIcons = true; app.configuration.newFileSound = true; app.configuration.newFileAutoOpen = false
            app.configuration.customNewFileEnabled = true; app.configuration.customNewFileMainMenu = false
            app.configuration.customNewFileName = "自定义创建新文件"
        case .destinations: app.configuration.destinationFolders = defaults.destinationFolders
        case .commonFolders: app.configuration.commonFolders = defaults.commonFolders
        case .icons:
            app.configuration.disabledActions.remove(MenuAction.setIcon.rawValue); app.configuration.disabledActions.remove(MenuAction.resetIcon.rawValue)
        case .toolbox:
            for action in SettingsTableController.toolboxActions { app.configuration.disabledActions.remove(action.rawValue) }
            app.configuration.applications = []; app.configuration.showIcons = true; app.configuration.mergeMenus = true
        case .general: break
        }
        app.persistSettings(); showSection(section)
    }
}

private final class SettingsNameField: NSTextField {
    var rowIndex = -1
    var canRename = false
    var editingStarted = false
    var originalValue = ""
    weak var owningTable: NSTableView?

    func beginRename() {
        guard canRename else { return }
        if !editingStarted { originalValue = stringValue }
        isEditable = true; isSelectable = true
        isBezeled = true; drawsBackground = true
        // selectText starts the window's field editor itself; a second focus request ends it.
        selectText(nil)
    }
    override func mouseDown(with event: NSEvent) {
        guard canRename else { super.mouseDown(with: event); return }
        if event.clickCount >= 2 {
            beginRename()
        } else if editingStarted {
            super.mouseDown(with: event)
        } else {
            owningTable?.mouseDown(with: event)
        }
    }
    override func cancelOperation(_ sender: Any?) {
        stringValue = originalValue
        owningTable?.window?.makeFirstResponder(owningTable)
    }
}

private final class SettingsTableView: NSTableView {
    var renameSelected: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 { renameSelected?() }
        else { super.keyDown(with: event) }
    }
}

private final class SettingsTableController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private unowned let app: AppController
    private let kind: SettingsSection
    let table = SettingsTableView()
    let scrollView = NSScrollView()
    var selectionChanged: ((Bool) -> Void)?
    var selectedRow: Int { table.selectedRow }
    private let rowDragType = NSPasteboard.PasteboardType("local.kingdee.RightClickAssistant.template-row")
    static let toolboxActions: [MenuAction] = [.fileInfo, .desktopLink, .airDrop, .share, .copyName, .folderByName, .cut, .paste,
        .dissolve, .wallpaper, .copyPath, .commonFolder, .deleteForever, .unhide, .hide, .hideExtension, .showExtension,
        .terminal, .chatGPT, .analyze, .otherApp, .zip, .sevenZip, .encryptedArchive, .extract,
        .png, .jpeg, .heic, .webp, .icns, .macIcons, .iosIcons, .qrCode, .baiduTranslate, .googleTranslate]

    init(app: AppController, kind: SettingsSection) {
        self.app = app; self.kind = kind; super.init()
        table.delegate = self; table.dataSource = self; table.rowHeight = 38
        table.intercellSpacing = NSSize(width: 10, height: 0); table.usesAlternatingRowBackgroundColors = false
        table.backgroundColor = NSColor(calibratedWhite: 0.96, alpha: 1)
        table.headerView = NSTableHeaderView(frame: NSRect(x: 0, y: 0, width: 0, height: 28))
        table.selectionHighlightStyle = .regular; table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.doubleAction = #selector(editName); table.target = self
        table.renameSelected = { [weak self] in self?.startEditing(row: self?.table.selectedRow ?? -1) }
        table.allowsMultipleSelection = false
        switch kind {
        case .newFile:
            column("enabled", title: "启用", width: 52); column("icon", title: "图标", width: 48)
            column("name", title: "显示名称（双击编辑 / 拖动排序）", width: 300, flexible: true)
            column("suffix", title: "后缀", width: 72); column("main", title: "主菜单", width: 64)
            table.registerForDraggedTypes([rowDragType]); table.setDraggingSourceOperationMask(.move, forLocal: true)
        case .destinations, .commonFolders:
            column("icon", title: "图标", width: 48); column("path", title: "真实路径", width: 330, flexible: true)
            column("name", title: "显示名称", width: 180)
        case .icons:
            column("icon", title: "图标", width: 56); column("name", title: "名称", width: 300, flexible: true)
        case .toolbox:
            column("enabled", title: "启用", width: 52); column("icon", title: "图标", width: 48)
            column("name", title: "显示名称", width: 300, flexible: true); column("details", title: "选项", width: 170)
        case .general: break
        }
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = table; scrollView.hasVerticalScroller = true; scrollView.autohidesScrollers = true
        scrollView.hasHorizontalScroller = false; scrollView.borderType = .lineBorder
        scrollView.drawsBackground = true; scrollView.backgroundColor = table.backgroundColor
    }
    private func column(_ id: String, title: String, width: CGFloat, flexible: Bool = false) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id)); column.title = title; column.width = width
        column.minWidth = flexible ? 150 : width; column.maxWidth = flexible ? 2000 : width
        column.resizingMask = flexible ? .autoresizingMask : []
        column.headerCell.font = .systemFont(ofSize: 12, weight: .medium)
        table.addTableColumn(column)
    }
    func numberOfRows(in tableView: NSTableView) -> Int {
        switch kind {
        case .newFile: return app.configuration.newFileTemplates.count + 1
        case .destinations: return app.configuration.destinationFolders.count
        case .commonFolders: return app.configuration.commonFolders.count
        case .icons: return IconPreset.all.count
        case .toolbox: return Self.toolboxActions.count + app.configuration.applications.count
        case .general: return 0
        }
    }
    func applicationIndex(forRow row: Int) -> Int? {
        let index = row - Self.toolboxActions.count
        return kind == .toolbox && index >= 0 && index < app.configuration.applications.count ? index : nil
    }
    func reload() { table.reloadData(); selectionChanged?(false) }
    func tableViewSelectionDidChange(_ notification: Notification) {
        let removable = table.selectedRow >= 0 && (kind != .newFile || table.selectedRow > 0) && (kind != .toolbox || applicationIndex(forRow: table.selectedRow) != nil)
        selectionChanged?(removable)
    }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = tableColumn?.identifier.rawValue else { return nil }
        let cell = (tableView.makeView(withIdentifier: tableColumn!.identifier, owner: self) as? NSTableCellView) ?? NSTableCellView()
        cell.subviews.forEach { $0.removeFromSuperview() }; cell.textField = nil; cell.imageView = nil
        cell.identifier = tableColumn?.identifier
        if column == "enabled" || column == "main" {
            if kind == .toolbox && row >= Self.toolboxActions.count { return cell }
            let button = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleRow(_:)))
            button.tag = row; button.identifier = NSUserInterfaceItemIdentifier(column)
            if kind == .newFile {
                let name: String
                if row == 0 {
                    name = app.configuration.customNewFileName
                    button.state = (column == "main" ? app.configuration.customNewFileMainMenu : app.configuration.customNewFileEnabled) ? .on : .off
                } else {
                    let entry = app.configuration.newFileTemplates[row - 1]; name = entry.name
                    button.state = (column == "main" ? entry.showInMainMenu : entry.enabled) ? .on : .off
                }
                button.setAccessibilityLabel((column == "main" ? "主菜单：" : "启用：") + name)
            } else if kind == .toolbox {
                if row < Self.toolboxActions.count {
                    let action = Self.toolboxActions[row]; button.state = app.configuration.enabled(action) ? .on : .off
                    button.setAccessibilityLabel("启用：" + action.title)
                } else {
                    button.state = app.configuration.enabled(.otherApp) ? .on : .off
                    button.setAccessibilityLabel("启用自定义应用")
                }
            }
            button.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(button)
            NSLayoutConstraint.activate([button.centerXAnchor.constraint(equalTo: cell.centerXAnchor), button.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
        } else if column == "icon" {
            let icon = NSImageView(); icon.image = image(for: row); icon.imageScaling = .scaleProportionallyUpOrDown
            icon.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(icon); cell.imageView = icon
            NSLayoutConstraint.activate([icon.centerXAnchor.constraint(equalTo: cell.centerXAnchor), icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                                        icon.widthAnchor.constraint(equalToConstant: 25), icon.heightAnchor.constraint(equalToConstant: 25)])
        } else {
            let field = SettingsNameField(labelWithString: text(for: row, column: column)); field.rowIndex = row
            field.owningTable = table
            field.canRename = column == "name" && [.newFile, .destinations].contains(kind)
            field.font = .systemFont(ofSize: 14); field.lineBreakMode = .byTruncatingMiddle
            field.translatesAutoresizingMaskIntoConstraints = false; field.delegate = self
            if column == "path" || column == "details" { field.textColor = .secondaryLabelColor; field.font = .systemFont(ofSize: 12) }
            cell.addSubview(field); cell.textField = field
            NSLayoutConstraint.activate([field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                                        field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4), field.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
        }
        return cell
    }
    private func image(for row: Int) -> NSImage? {
        let workspace = NSWorkspace.shared
        switch kind {
        case .newFile:
            if row == 0 { return workspace.icon(for: .data) }
            let item = app.configuration.newFileTemplates[row - 1]
            if let path = item.sourcePath { return workspace.icon(forFile: path) }
            let type = UTType(filenameExtension: URL(fileURLWithPath: item.filename).pathExtension) ?? .data
            return workspace.icon(for: type)
        case .destinations: return workspace.icon(forFile: app.configuration.destinationFolders[row].path)
        case .commonFolders: return workspace.icon(forFile: app.configuration.commonFolders[row])
        case .icons: return NativeFileIcons.image(for: IconPreset.all[row], size: 26)
        case .toolbox:
            if let index = applicationIndex(forRow: row) { return workspace.icon(forFile: app.configuration.applications[index].path) }
            let action = Self.toolboxActions[row]
            return SettingsView.tileIcon(action.icon, color: color(for: action), size: 26)
        case .general: return nil
        }
    }
    private func color(for action: MenuAction) -> NSColor {
        switch action {
        case .deleteForever: return .systemRed
        case .zip, .sevenZip, .encryptedArchive, .extract: return .systemPurple
        case .hide, .unhide, .hideExtension, .showExtension: return .systemGray
        case .terminal: return .darkGray
        case .commonFolder: return .systemPink
        default: return .systemTeal
        }
    }
    private func text(for row: Int, column: String) -> String {
        switch kind {
        case .newFile:
            if row == 0 { return column == "name" ? app.configuration.customNewFileName : "" }
            let item = app.configuration.newFileTemplates[row - 1]
            return column == "name" ? item.name : URL(fileURLWithPath: item.filename).pathExtension
        case .destinations:
            let item = app.configuration.destinationFolders[row]
            return column == "path" ? (item.path as NSString).abbreviatingWithTildeInPath : item.name
        case .commonFolders:
            let path = app.configuration.commonFolders[row]
            return column == "path" ? (path as NSString).abbreviatingWithTildeInPath : URL(fileURLWithPath: path).lastPathComponent
        case .icons: return IconPreset.all[row].name
        case .toolbox:
            if let index = applicationIndex(forRow: row) {
                let appRef = app.configuration.applications[index]
                return column == "name" ? "进入 " + appRef.name : (appRef.path as NSString).abbreviatingWithTildeInPath
            }
            let action = Self.toolboxActions[row]
            if column == "name" { return action.title }
            if action == .deleteForever { return "需要再次确认" }
            if action == .terminal { return "仅文件夹" }
            if [.qrCode, .baiduTranslate, .googleTranslate].contains(action) { return "选中文字后的服务" }
            return ""
        case .general: return ""
        }
    }
    @objc private func toggleRow(_ button: NSButton) {
        let row = button.tag
        guard row >= 0, row < numberOfRows(in: table) else { return }
        if kind == .newFile {
            if row == 0 {
                if button.identifier?.rawValue == "main" { app.configuration.customNewFileMainMenu = button.state == .on }
                else { app.configuration.customNewFileEnabled = button.state == .on }
            } else if button.identifier?.rawValue == "main" {
                app.configuration.newFileTemplates[row - 1].showInMainMenu = button.state == .on
            } else {
                if button.state == .on {
                    do { _ = try TemplatePolicy.sourceURL(for: app.configuration.newFileTemplates[row - 1], resources: Bundle.main.resourceURL ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Resources")) }
                    catch { button.state = .off; app.error(error); return }
                }
                app.configuration.newFileTemplates[row - 1].enabled = button.state == .on
            }
        } else if kind == .toolbox {
            let action = row < Self.toolboxActions.count ? Self.toolboxActions[row] : .otherApp
            if button.state == .on { app.configuration.disabledActions.remove(action.rawValue) }
            else { app.configuration.disabledActions.insert(action.rawValue) }
            if row >= Self.toolboxActions.count { table.reloadData() }
        }
        app.persistSettings()
    }
    @objc private func editName() { startEditing(row: table.clickedRow) }
    private func startEditing(row: Int) {
        guard [.newFile, .destinations].contains(kind), row >= 0, row < numberOfRows(in: table),
              let index = table.tableColumns.firstIndex(where: { $0.identifier.rawValue == "name" }),
              let cell = table.view(atColumn: index, row: row, makeIfNecessary: true) as? NSTableCellView,
              let field = cell.textField as? SettingsNameField else { return }
        field.beginRename()
    }
    func controlTextDidBeginEditing(_ notification: Notification) {
        guard let field = notification.object as? SettingsNameField else { return }
        field.editingStarted = true
    }
    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? SettingsNameField, field.editingStarted else { return }
        let row = field.rowIndex
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = value.isEmpty ? field.originalValue : value
        // Keep the live cell in place so ending one edit cannot destroy a new field editor.
        field.editingStarted = false; field.stringValue = name
        field.isEditable = false; field.isSelectable = false; field.isBezeled = false; field.drawsBackground = false
        guard row >= 0, row < numberOfRows(in: table), name != field.originalValue else { return }
        if kind == .newFile {
            if row == 0 { app.configuration.customNewFileName = name }
            else { app.configuration.newFileTemplates[row - 1].name = name }
        } else if kind == .destinations { app.configuration.destinationFolders[row].name = name }
        app.persistSettings()
    }
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard kind == .newFile, row > 0, row <= app.configuration.newFileTemplates.count else { return nil }
        let item = NSPasteboardItem(); item.setString(app.configuration.newFileTemplates[row - 1].id, forType: rowDragType); return item
    }
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int,
                   proposedDropOperation operation: NSTableView.DropOperation) -> NSDragOperation {
        guard kind == .newFile, (info.draggingSource as? NSTableView) === tableView,
              info.draggingPasteboard.string(forType: rowDragType) != nil else { return [] }
        tableView.setDropRow(max(row, 1), dropOperation: .above); return .move
    }
    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        guard kind == .newFile, let id = info.draggingPasteboard.string(forType: rowDragType),
              let source = app.configuration.newFileTemplates.firstIndex(where: { $0.id == id }) else { return false }
        var destination = min(max(row - 1, 0), app.configuration.newFileTemplates.count)
        let item = app.configuration.newFileTemplates.remove(at: source)
        if source < destination { destination -= 1 }
        app.configuration.newFileTemplates.insert(item, at: destination)
        app.persistSettings(); table.reloadData(); table.selectRowIndexes(IndexSet(integer: destination + 1), byExtendingSelection: false)
        return true
    }
}
