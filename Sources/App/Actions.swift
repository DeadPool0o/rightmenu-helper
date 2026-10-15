import AppKit
import CoreImage
import UniformTypeIdentifiers

final class ActionRunner {
    unowned let app: AppController
    private let cutType = NSPasteboard.PasteboardType("local.rightclick-assistant.cut")
    init(_ app: AppController) { self.app = app }

    func execute(_ action: MenuAction, selection: Selection?, options: ActionOptions = ActionOptions()) {
        ActionLog.record("execute action=" + action.rawValue + " selectionCount=" + String(selection?.urls.count ?? 0))
        if action == .settings { app.showWindow(); return }
        guard let s = selection else { app.message("没有选中的项目", "请在桌面或访达中右键文件或文件夹后执行此操作。"); return }
        do {
            switch action {
            case .chatGPT: try openChatGPT(s, analyze: false)
            case .analyze: try openChatGPT(s, analyze: true)
            case .otherApp:
                if let path = options.application {
                    guard app.configuration.applications.contains(where: { $0.path == path }) else { throw AssistantError.message("请先在设置中添加这个应用。") }
                    try openURLs(s.urls, appURL: URL(fileURLWithPath: path))
                } else { chooseApp(s) }
            case .terminal:
                guard s.urls.allSatisfy(MenuPolicy.isFolder) else { throw AssistantError.message("进入终端需要选中文件夹。") }
                for folder in s.urls { try open(folder, bundleID: "com.apple.Terminal") }
            case .copyPath, .copyName:
                let text = s.urls.map { action == .copyPath ? $0.path : $0.lastPathComponent }.joined(separator: "\n")
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
                app.status("已复制 \(s.urls.count) 项")
            case .cut:
                NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects(s.urls as [NSURL])
                NSPasteboard.general.setData(try JSONEncoder().encode(s.urls.map(\.path)), forType: cutType)
                app.status("已剪切 \(s.urls.count) 项，选择目标文件夹后粘贴")
            case .paste: paste(into: s.directory)
            case .copyTo, .moveTo:
                if let dir = options.destination.map({ URL(fileURLWithPath: $0, isDirectory: true) }) ?? directoryPanel("选择目标文件夹", initial: s.directory) {
                    app.work(action.title) { let errors = FilePolicy.transfer(s.urls, to: dir, move: action == .moveTo)
                        if !errors.isEmpty { throw AssistantError.message(errors.joined(separator: "\n")) }
                        return "已处理 \(s.urls.count) 项" }
                }
            case .newText, .newMarkdown: try newTemplate(id: action == .newText ? "builtin-txt" : "builtin-markdown", in: s.directory)
            case .newEmpty: try newEmptyFile(in: s.directory)
            case .newTemplate:
                guard let id = options.template else { throw AssistantError.message("请从右键菜单选择具体的文件类型。") }
                try newTemplate(id: id, in: s.directory)
            case .commonFolder: commonFolder()
            case .fileInfo: showInfo(s)
            case .folderByName:
                app.work(action.title) {
                    for u in s.urls {
                        let target = FilePolicy.uniqueURL(in: u.deletingLastPathComponent(), name: u.deletingPathExtension().lastPathComponent)
                        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
                    }; return "已创建 \(s.urls.count) 个文件夹"
                }
            case .dissolve: dissolve(s)
            case .desktopLink:
                let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
                app.work(action.title) {
                    for source in s.urls {
                        try FileManager.default.createSymbolicLink(at: FilePolicy.uniqueURL(in: dir, name: source.lastPathComponent), withDestinationURL: source)
                    }; return "已创建快捷方式"
                }
            case .hide, .unhide, .hideExtension, .showExtension:
                app.work(action.title) {
                    for var u in s.urls {
                        var v = URLResourceValues()
                        if action == .hide || action == .unhide { v.isHidden = action == .hide }
                        else { v.hasHiddenExtension = action == .hideExtension }
                        try u.setResourceValues(v)
                    }; return "已更新 \(s.urls.count) 项"
                }
            case .deleteForever:
                if confirm("永久删除 \(s.urls.count) 项？", detail: "这些项目不会进入废纸篓，删除后无法撤销。", destructive: true) {
                    app.work("正在删除") { for u in s.urls { try FileManager.default.removeItem(at: u) }; return "已永久删除" }
                }
            case .zip, .sevenZip: compress(s, seven: action == .sevenZip)
            case .encryptedArchive:
                try kekaCompression(s, encrypted: true)
            case .extract:
                if s.urls.allSatisfy({ $0.pathExtension.lowercased() == "zip" }) {
                    app.work(action.title) { for u in s.urls { _ = try CommandWork.extractZIP(u) }; return "已解压到各自的独立文件夹" }
                } else { try openURLs(s.urls, appURL: applicationURL(bundleID: "com.aone.keka", fallback: "/Applications/Keka.app")) }
            case .png, .jpeg, .heic, .webp:
                app.work(action.title) { for u in s.urls { _ = try MediaWork.convert(u, action: action) }; return "已转换，文件保存在原目录" }
            case .macIcons, .iosIcons, .icns:
                app.work(action.title) {
                    for u in s.urls {
                        let folder = try MediaWork.iconSet(u, ios: action == .iosIcons)
                        if action == .icns {
                            defer { try? FileManager.default.removeItem(at: folder) }
                            let output = FilePolicy.uniqueURL(in: u.deletingLastPathComponent(), name: u.deletingPathExtension().lastPathComponent + ".icns")
                            try CommandWork.run("/usr/bin/iconutil", ["-c", "icns", folder.path, "-o", output.path])
                        }
                    }; return "已生成，文件保存在原目录"
                }
            case .wallpaper:
                for screen in NSScreen.screens { try NSWorkspace.shared.setDesktopImageURL(s.urls[0], for: screen, options: [:]) }
                app.status("已设置壁纸")
            case .setIcon:
                if let identifier = options.icon {
                    guard let preset = IconPreset.all.first(where: { $0.symbol == identifier }),
                          let image = NativeFileIcons.image(for: preset) else { throw AssistantError.message("系统图标不可用。") }
                    try applyIcon(image, to: s.urls)
                    app.status("已设置图标"); break
                }
                let p = NSOpenPanel(); p.title = "选择图标图片"; p.allowedContentTypes = [.image]
                guard p.runModal() == .OK, let u = p.url, let image = NSImage(contentsOf: u) else { return }
                try applyIcon(image, to: s.urls)
                app.status("已设置图标")
            case .resetIcon:
                try applyIcon(nil, to: s.urls)
                app.status("已恢复图标")
            case .airDrop:
                guard let service = NSSharingService(named: .sendViaAirDrop) else { throw AssistantError.message("隔空投送当前不可用。") }
                service.perform(withItems: s.urls)
            case .share:
                app.share(s.urls)
            case .qrCode:
                if let text = textDialog("生成二维码", initial: NSPasteboard.general.string(forType: .string) ?? "") {
                    try showQR(text)
                }
            case .baiduTranslate, .googleTranslate:
                guard let text = textDialog("翻译文本", initial: NSPasteboard.general.string(forType: .string) ?? "") else { return }
                translate(text, google: action == .googleTranslate)
            case .settings: break
            }
        } catch { app.error(error) }
    }

    private func applyIcon(_ image: NSImage?, to urls: [URL]) throws {
        for url in urls { try FileIconWork.apply(image, to: url) }
    }

    func translate(_ text: String, google: Bool) {
        var c = URLComponents(string: google ? "https://translate.google.com/" : "https://fanyi.baidu.com/")!
        c.queryItems = google ? [URLQueryItem(name: "sl", value: "auto"), URLQueryItem(name: "tl", value: "zh-CN"), URLQueryItem(name: "text", value: text), URLQueryItem(name: "op", value: "translate")] : [URLQueryItem(name: "query", value: text)]
        if let url = c.url { NSWorkspace.shared.open(url) }
    }

    private func applicationURL(bundleID: String, fallback: String? = nil) throws -> URL {
        if let fallback, FileManager.default.fileExists(atPath: fallback) { return URL(fileURLWithPath: fallback) }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw AssistantError.message("未找到应用，请先安装或在设置中指定应用。")
        }; return url
    }
    private func open(_ url: URL, bundleID: String) throws { try openURLs([url], appURL: applicationURL(bundleID: bundleID)) }
    func openURLs(_ urls: [URL], appURL: URL) throws {
        guard Bundle(url: appURL)?.bundleIdentifier != nil else { throw AssistantError.message("请选择有效的 .app 应用。") }
        NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            DispatchQueue.main.async {
                if let error { self.app.error(error) }
                else { ActionLog.record("opened application=" + (Bundle(url: appURL)?.bundleIdentifier ?? "unknown")); self.app.status("已交给 " + appURL.deletingPathExtension().lastPathComponent) }
            }
        }
    }
    private func openChatGPT(_ selection: Selection, analyze: Bool) throws {
        let target = try NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") ??
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.chat") ??
            applicationURL(bundleID: "com.openai.codex", fallback: "/Applications/ChatGPT.app")
        let identifier = Bundle(url: target)?.bundleIdentifier
        if analyze {
            guard identifier == "com.openai.codex" else { throw AssistantError.message("预填本地分析提示词需要支持 codex:// 的新版 ChatGPT。直接打开仍可使用。") }
            guard let prompt = textDialog("让 ChatGPT 分析", initial: app.configuration.analysisPrompt) else { return }
            try openURLs([ChatGPTLink.draft(selection: selection, instruction: prompt)], appURL: target)
        } else {
            var documents: [URL] = []; var folders: [URL] = []
            for u in selection.urls {
                let v = try u.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
                if identifier == "com.openai.codex" && v.isDirectory == true && v.isPackage != true { folders.append(ChatGPTLink.folder(u)) }
                else { documents.append(u) }
            }
            if !documents.isEmpty { try openURLs(documents, appURL: target) }
            for folder in folders { try openURLs([folder], appURL: target) }
        }
    }
    private func chooseApp(_ s: Selection) {
        let alert = NSAlert(); alert.messageText = "用哪个 App 打开？"
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 340, height: 28))
        popup.addItems(withTitles: app.configuration.applications.map(\.name) + ["选择其他应用…"])
        alert.accessoryView = popup; alert.addButton(withTitle: "打开"); alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            if popup.indexOfSelectedItem < app.configuration.applications.count {
                try openURLs(s.urls, appURL: URL(fileURLWithPath: app.configuration.applications[popup.indexOfSelectedItem].path))
            } else {
                let p = NSOpenPanel(); p.title = "选择应用"; p.allowedContentTypes = [.applicationBundle]; p.directoryURL = URL(fileURLWithPath: "/Applications")
                if p.runModal() == .OK, let u = p.url { app.addApplication(u); try openURLs(s.urls, appURL: u) }
            }
        } catch { app.error(error) }
    }
    func directoryPanel(_ title: String, initial: URL? = nil) -> URL? {
        NSApp.activate(ignoringOtherApps: true)
        let p = NSOpenPanel(); p.title = title; p.canChooseFiles = false; p.canChooseDirectories = true
        p.canCreateDirectories = true; p.directoryURL = initial
        return p.runModal() == .OK ? p.url : nil
    }
    func textDialog(_ title: String, initial: String, singleLine: Bool = false) -> String? {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert(); a.messageText = title
        let field = NSTextField(frame: NSRect(x: 0, y: 0,
            width: singleLine ? 320 : 400, height: singleLine ? 24 : 64))
        field.stringValue = initial
        field.isEditable = true; field.isSelectable = true; field.usesSingleLineMode = singleLine
        field.cell?.wraps = !singleLine
        field.cell?.isScrollable = singleLine
        a.accessoryView = field; a.addButton(withTitle: "确定"); a.addButton(withTitle: "取消")
        a.window.title = title
        a.window.initialFirstResponder = field
        return a.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }
    private func confirm(_ title: String, detail: String, destructive: Bool = false) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert(); a.messageText = title; a.informativeText = detail
        a.alertStyle = destructive ? .critical : .warning
        a.addButton(withTitle: "取消"); a.addButton(withTitle: "继续")
        return a.runModal() == .alertSecondButtonReturn
    }
    private func paste(into dir: URL) {
        let pb = NSPasteboard.general
        let cutPaths = pb.data(forType: cutType).flatMap { try? JSONDecoder().decode([String].self, from: $0) }
        let urls = cutPaths?.map { URL(fileURLWithPath: $0) } ?? (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? [])
        let changeCount = pb.changeCount
        guard !urls.isEmpty else { app.message("没有可粘贴的文件", "请先在 Finder 复制文件，或用右键助手剪切文件。"); return }
        app.work("正在粘贴") {
            let errors = FilePolicy.transfer(urls, to: dir, move: cutPaths != nil)
            if cutPaths != nil {
                let remaining = urls.filter { FileManager.default.fileExists(atPath: $0.path) }.map(\.path)
                DispatchQueue.main.async {
                    guard pb.changeCount == changeCount else { return }
                    if remaining.isEmpty { pb.clearContents() }
                    else { pb.clearContents(); pb.writeObjects(remaining.map { NSURL(fileURLWithPath: $0) });
                        pb.setData(try? JSONEncoder().encode(remaining), forType: self.cutType) }
                }
            }
            if !errors.isEmpty { throw AssistantError.message(errors.joined(separator: "\n")) }
            return "已粘贴 \(urls.count) 项"
        }
    }
    private func newTemplate(id: String, in dir: URL) throws {
        guard let template = app.configuration.newFileTemplates.first(where: { $0.id == id && $0.enabled }) else {
            throw AssistantError.message("这个文件类型已停用或移除，请重新打开右键菜单。")
        }
        let suggested = template.filename.contains(".") ? "未命名." + URL(fileURLWithPath: template.filename).pathExtension : "未命名"
        guard let filename = textDialog("新建 " + template.name, initial: suggested, singleLine: true) else { return }
        let target = try TemplatePolicy.create(template, name: filename, in: dir, resources: Bundle.main.resourceURL!)
        newFileCreated(target)
    }
    private func newEmptyFile(in dir: URL) throws {
        guard app.configuration.customNewFileEnabled else { throw AssistantError.message("自定义创建新文件已停用。") }
        guard let name = textDialog(app.configuration.customNewFileName, initial: "未命名.txt", singleLine: true) else { return }
        try FilePolicy.validateName(name)
        guard TemplatePolicy.emptyFileAllowed(extension: URL(fileURLWithPath: name).pathExtension) else {
            throw AssistantError.message("这种格式需要有效文档模板，请从新建文件菜单选择相应类型，或在设置中添加模板文件。")
        }
        let target = dir.appendingPathComponent(name); try Data().write(to: target, options: .withoutOverwriting)
        newFileCreated(target)
    }
    private func newFileCreated(_ target: URL) {
        if app.configuration.newFileSound { NSSound(named: NSSound.Name("Tink"))?.play() }
        if app.configuration.newFileAutoOpen { NSWorkspace.shared.open(target) }
        else { NSWorkspace.shared.activateFileViewerSelecting([target]) }
        ActionLog.record("new file created")
        app.status("已创建 " + target.lastPathComponent)
    }
    private func commonFolder() {
        let a = NSAlert(); a.messageText = "常用目录"
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 360, height: 28))
        popup.addItems(withTitles: app.configuration.commonFolders + ["添加目录…"])
        a.accessoryView = popup; a.addButton(withTitle: "打开"); a.addButton(withTitle: "取消")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        if popup.indexOfSelectedItem < app.configuration.commonFolders.count {
            NSWorkspace.shared.open(URL(fileURLWithPath: app.configuration.commonFolders[popup.indexOfSelectedItem]))
        } else if let dir = directoryPanel("添加常用目录") {
            if !app.configuration.commonFolders.contains(dir.path) { app.configuration.commonFolders.append(dir.path); try? app.configuration.save() }
            NSWorkspace.shared.open(dir)
        }
    }
    private func dissolve(_ s: Selection) {
        guard confirm("解散所选文件夹？", detail: "将内容移动到各自上一级目录。同名项目会保留在原文件夹中，不会覆盖。") else { return }
        app.work("正在整理文件夹") {
            var errors: [String] = []
            for folder in s.urls {
                let children = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                errors += FilePolicy.transfer(children, to: folder.deletingLastPathComponent(), move: true)
                if (try FileManager.default.contentsOfDirectory(atPath: folder.path)).isEmpty { try FileManager.default.removeItem(at: folder) }
            }
            if !errors.isEmpty { throw AssistantError.message(errors.joined(separator: "\n")) }; return "文件夹整理完成"
        }
    }
    private func showInfo(_ s: Selection) {
        let info = s.urls.prefix(30).map { u -> String in
            let v = try? u.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey, .isDirectoryKey])
            return "\(u.lastPathComponent)\n\(u.path)\n类型：\(v?.isDirectory == true ? "文件夹" : u.pathExtension)\n大小：\(v?.fileSize ?? 0) 字节\n修改：\(v?.contentModificationDate?.description ?? "未知")"
        }.joined(separator: "\n\n")
        app.message("文件信息（\(s.urls.count) 项）", info + (s.urls.count > 30 ? "\n\n仅显示前 30 项。" : ""))
    }
    private func compress(_ s: Selection, seven: Bool) {
        if seven && CommandWork.sevenZip == nil {
            do { try kekaCompression(s, encrypted: false) } catch { app.error(error) }; return
        }
        let ext = seven ? "7z" : "zip"
        guard let name = textDialog("压缩文件名称", initial: s.urls.count == 1 ? s.urls[0].deletingPathExtension().lastPathComponent + "." + ext : "归档." + ext, singleLine: true) else { return }
        do {
            try FilePolicy.validateName(name)
            let destination = s.urls[0].deletingLastPathComponent().appendingPathComponent(name)
            app.work("正在压缩") { try CommandWork.compress(s.urls, to: destination, seven: seven); return "已生成 " + destination.lastPathComponent }
        } catch { app.error(error) }
    }
    private func kekaCompression(_ s: Selection, encrypted: Bool) throws {
        let target = try applicationURL(bundleID: "com.aone.keka", fallback: "/Applications/Keka.app")
        let a = NSAlert(); a.messageText = encrypted ? "用 Keka 加密压缩" : "用 Keka 压缩为 7z"
        a.informativeText = encrypted ? "先在 Keka 中设置压缩格式和密码，然后再点“已设置，交给 Keka”。" :
            "先在 Keka 中选择 7z 格式，然后再点“已设置，交给 Keka”。"
        a.addButton(withTitle: "打开 Keka 设置"); a.addButton(withTitle: "已设置，交给 Keka"); a.addButton(withTitle: "取消")
        let result = a.runModal()
        if result == .alertFirstButtonReturn {
            NSWorkspace.shared.openApplication(at: target, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
            app.status("设置好 Keka 后，请再次选择此操作")
        } else if result == .alertSecondButtonReturn { try openURLs(s.urls, appURL: target) }
    }
    func showQR(_ text: String) throws {
        let image = try MediaWork.qr(text)
        let a = NSAlert(); a.messageText = "二维码"
        let view = NSImageView(frame: NSRect(x: 0, y: 0, width: 260, height: 260)); view.image = image
        view.imageScaling = .scaleProportionallyUpOrDown; a.accessoryView = view
        a.addButton(withTitle: "保存 PNG…"); a.addButton(withTitle: "关闭")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let p = NSSavePanel(); p.allowedContentTypes = [.png]; p.nameFieldStringValue = "二维码.png"
        guard p.runModal() == .OK, let target = p.url, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        // NSSavePanel presents the user's overwrite decision; write via a fresh sibling and atomic replacement.
        let temporary = target.deletingLastPathComponent().appendingPathComponent(".qr-" + UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try MediaWork.encode(cg, type: "public.png", to: temporary)
        if FileManager.default.fileExists(atPath: target.path) { _ = try FileManager.default.replaceItemAt(target, withItemAt: temporary) }
        else { try FileManager.default.moveItem(at: temporary, to: target) }
    }
}
