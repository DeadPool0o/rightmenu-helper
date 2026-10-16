import AppKit
import UniformTypeIdentifiers

/// Read the installed-app catalog only when choosing an app, outside the Finder extension.
final class ApplicationPicker: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private let alert = NSAlert()
    private let search = NSSearchField()
    private let table = NSTableView()
    private let summary = NSTextField(labelWithString: "正在读取本机应用…")
    private var applications: [AppReference] = []
    private var filtered: [AppReference] = []
    private var excludedPaths = Set<String>()

    func choose(multiple: Bool, excluding saved: [AppReference] = [], opening: Bool = false) -> [URL] {
        excludedPaths = Set(saved.map { URL(fileURLWithPath: $0.path).resolvingSymlinksInPath().path })
        alert.messageText = opening ? "选择打开应用" : "添加打开方式"
        alert.informativeText = opening
            ? "所选文件或文件夹将交给此应用，并将应用保存到右键“打开方式”中。"
            : "从本机已安装的应用中选择，添加后会保存在右键“打开方式”中。"
        alert.addButton(withTitle: opening ? "打开并保存" : "添加")
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: "浏览其他位置…")
        alert.buttons[0].isEnabled = false
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 380))
        search.frame = NSRect(x: 0, y: 350, width: 560, height: 28)
        search.placeholderString = "搜索应用名称或路径"; search.delegate = self
        search.setAccessibilityLabel("搜索本机应用")
        accessory.addSubview(search)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 28, width: 560, height: 310))
        scroll.hasVerticalScroller = true; scroll.borderType = .lineBorder
        table.delegate = self; table.dataSource = self; table.rowHeight = 36
        table.allowsMultipleSelection = multiple
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.target = self; table.doubleAction = #selector(acceptSelection)
        let name = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        name.title = "应用"; name.width = 210; table.addTableColumn(name)
        let path = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("path"))
        path.title = "安装位置"; path.width = 325; table.addTableColumn(path)
        table.setAccessibilityLabel("本机已安装的应用")
        scroll.documentView = table; accessory.addSubview(scroll)
        summary.frame = NSRect(x: 0, y: 0, width: 560, height: 20)
        summary.font = .systemFont(ofSize: 12); summary.textColor = .secondaryLabelColor
        accessory.addSubview(summary)
        alert.accessoryView = accessory; alert.window.initialFirstResponder = search
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let found = ApplicationCatalog.scan()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.applications = found.filter { !self.excludedPaths.contains($0.path) }
                self.filterApplications()
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return table.selectedRowIndexes.compactMap { index in
                filtered.indices.contains(index) ? URL(fileURLWithPath: filtered[index].path) : nil
            }
        case .alertThirdButtonReturn:
            let panel = NSOpenPanel(); panel.title = "选择本机应用"
            panel.allowedContentTypes = [.applicationBundle]; panel.allowsMultipleSelection = multiple
            panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
            panel.canChooseDirectories = false
            return panel.runModal() == .OK ? panel.urls : []
        default: return []
        }
    }

    private func filterApplications() {
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        filtered = applications.filter {
            query.isEmpty || $0.name.localizedStandardContains(query) || $0.path.localizedStandardContains(query)
        }
        table.deselectAll(nil); table.reloadData(); alert.buttons[0].isEnabled = false
        summary.stringValue = filtered.isEmpty
            ? "没有可添加的匹配应用；可搜索其他名称或浏览其他位置。"
            : "共 \(filtered.count) 个应用" + (table.allowsMultipleSelection ? "，可按住 ⌘ 多选。" : "")
    }
    func controlTextDidChange(_ notification: Notification) { filterApplications() }
    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }
    func tableViewSelectionDidChange(_ notification: Notification) {
        alert.buttons[0].isEnabled = !table.selectedRowIndexes.isEmpty
    }
    @objc private func acceptSelection() {
        guard !table.selectedRowIndexes.isEmpty else { return }
        alert.buttons[0].performClick(nil)
    }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let reference = filtered[row]
        if tableColumn?.identifier.rawValue == "path" {
            let cell = NSTableCellView()
            let field = NSTextField(labelWithString: (reference.path as NSString).abbreviatingWithTildeInPath)
            field.font = .systemFont(ofSize: 12); field.textColor = .secondaryLabelColor
            field.lineBreakMode = .byTruncatingMiddle; field.toolTip = reference.path
            field.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(field); cell.textField = field
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                field.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            return cell
        }
        let cell = NSTableCellView()
        let icon = NSImageView(); icon.image = NSWorkspace.shared.icon(forFile: reference.path)
        icon.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(icon)
        let field = NSTextField(labelWithString: reference.name)
        field.translatesAutoresizingMaskIntoConstraints = false; field.lineBreakMode = .byTruncatingTail
        cell.addSubview(field); cell.imageView = icon; cell.textField = field
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 24), icon.heightAnchor.constraint(equalToConstant: 24),
            field.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4)
        ])
        return cell
    }
}
