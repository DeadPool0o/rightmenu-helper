import Foundation
import os
import Darwin

enum ActionLog {
    private static let logger = Logger(subsystem: "local.kingdee.RightClickAssistant", category: "Actions")
    static func record(_ text: String) { logger.notice("\(text, privacy: .public)") }
}

enum MenuAction: String, CaseIterable, Codable {
    case otherApp, terminal, copyPath, copyName, cut, paste
    case copyTo, moveTo, newText, newMarkdown, newTemplate, newEmpty, commonFolder
    case fileInfo, folderByName, dissolve, desktopLink, hide, unhide, hideExtension, showExtension
    case deleteForever, zip, sevenZip, encryptedArchive, extract
    case png, jpeg, heic, webp, icns, macIcons, iosIcons, wallpaper, setIcon, resetIcon
    case airDrop, share, qrCode, baiduTranslate, googleTranslate, settings

    var title: String {
        switch self {
        case .otherApp: return "打开方式"
        case .terminal: return "进入终端"
        case .copyPath: return "拷贝路径"
        case .copyName: return "拷贝文件（夹）名称"
        case .cut: return "剪切"
        case .paste: return "粘贴到此处"
        case .copyTo: return "复制文件到…"
        case .moveTo: return "移动文件到…"
        case .newText: return "新建 TXT…"
        case .newMarkdown: return "新建 Markdown…"
        case .newTemplate: return "从模板新建…"
        case .newEmpty: return "自定义创建新文件"
        case .commonFolder: return "打开常用目录…"
        case .fileInfo: return "文件信息"
        case .folderByName: return "按文件名创建文件夹"
        case .dissolve: return "解散文件夹…"
        case .desktopLink: return "发送快捷方式到桌面"
        case .hide: return "隐藏所选文件"
        case .unhide: return "取消隐藏"
        case .hideExtension: return "隐藏扩展名"
        case .showExtension: return "显示扩展名"
        case .deleteForever: return "永久删除"
        case .zip: return "压缩为 ZIP…"
        case .sevenZip: return "压缩为 7z…"
        case .encryptedArchive: return "加密压缩（Keka）…"
        case .extract: return "解压到独立文件夹"
        case .png: return "转换为 PNG"
        case .jpeg: return "转换为 JPG"
        case .heic: return "转换为 HEIC"
        case .webp: return "转换为 WebP"
        case .icns: return "转换为 ICNS"
        case .macIcons: return "生成 Mac 图标集"
        case .iosIcons: return "生成 iOS 图标集"
        case .wallpaper: return "设为桌面壁纸"
        case .setIcon: return "设置文件图标…"
        case .resetIcon: return "恢复文件图标"
        case .airDrop: return "隔空投送"
        case .share: return "分享…"
        case .qrCode: return "生成二维码…"
        case .baiduTranslate: return "百度翻译所选文本"
        case .googleTranslate: return "谷歌翻译所选文本"
        case .settings: return "右键助手设置…"
        }
    }

    static let groups: [(String, [MenuAction])] = [
        ("应用与终端", [.otherApp, .terminal]),
        ("新建与文件操作", [.newText, .newMarkdown, .newTemplate, .cut, .paste, .copyTo, .moveTo,
                        .copyPath, .copyName, .commonFolder, .folderByName, .dissolve, .desktopLink, .fileInfo]),
        ("显示与图标", [.hide, .unhide, .hideExtension, .showExtension, .setIcon, .resetIcon]),
        ("压缩与解压", [.zip, .sevenZip, .encryptedArchive, .extract]),
        ("图片与壁纸", [.png, .jpeg, .heic, .webp, .icns, .macIcons, .iosIcons, .wallpaper]),
        ("分享与文本", [.airDrop, .share, .qrCode, .baiduTranslate, .googleTranslate]),
        ("删除", [.deleteForever])
    ]
    static let primary: [MenuAction] = [.otherApp, .moveTo, .copyTo, .copyName, .copyPath, .terminal]

    var menuTag: Int { Self.allCases.firstIndex(of: self)! + 1 }
    init?(menuTag: Int) {
        guard menuTag > 0, menuTag <= Self.allCases.count else { return nil }
        self = Self.allCases[menuTag - 1]
    }

    var icon: String {
        switch self {
        case .terminal: return "terminal"
        case .moveTo: return "folder"
        case .copyTo: return "doc.on.doc"
        case .copyName: return "textformat"
        case .copyPath: return "link"
        case .newText, .newMarkdown, .newTemplate, .newEmpty: return "doc.badge.plus"
        case .deleteForever: return "trash"
        case .cut: return "scissors"
        case .paste: return "doc.on.clipboard"
        case .hide: return "eye.slash"
        case .unhide: return "eye"
        case .zip, .sevenZip, .encryptedArchive, .extract: return "archivebox"
        case .share, .airDrop: return "square.and.arrow.up"
        case .otherApp: return "app"
        case .settings: return "gearshape"
        default: return "doc"
        }
    }
}

enum MenuPolicy {
    static func isFolder(_ url: URL) -> Bool {
        let v = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        let package = v?.isPackage ?? ["app", "bundle", "framework", "pages", "numbers", "key"].contains(url.pathExtension.lowercased())
        return (v?.isDirectory ?? url.hasDirectoryPath) && !package
    }
    static func allows(_ action: MenuAction, selected: [URL]) -> Bool {
        if action == .settings || action == .commonFolder { return true }
        let folders = !selected.isEmpty && selected.allSatisfy(isFolder)
        switch action {
        case .newText, .newMarkdown, .newTemplate, .newEmpty, .paste: return selected.isEmpty || folders
        case .terminal, .dissolve: return folders
        case .png, .jpeg, .heic, .webp, .icns, .macIcons, .iosIcons, .wallpaper:
            let images = ["png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "gif", "bmp", "webp", "icns", "ico", "avif"]
            return !selected.isEmpty && selected.allSatisfy { !isFolder($0) && images.contains($0.pathExtension.lowercased()) }
        case .extract:
            let archives = ["zip", "7z", "rar", "tar", "gz", "bz2", "xz", "tgz", "tbz", "txz"]
            return !selected.isEmpty && selected.allSatisfy { !isFolder($0) && archives.contains($0.pathExtension.lowercased()) }
        case .folderByName, .hideExtension, .showExtension:
            return !selected.isEmpty && selected.allSatisfy { !isFolder($0) }
        case .qrCode, .baiduTranslate, .googleTranslate: return false // Text selections use macOS Services.
        default: return !selected.isEmpty
        }
    }
}

enum AssistantError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}

struct Selection: Equatable {
    let urls: [URL]
    let directory: URL

    init(urls: [URL], directory: URL? = nil) throws {
        guard !urls.isEmpty, urls.count <= 256, urls.allSatisfy({ $0.isFileURL && $0.path.hasPrefix("/") }) else {
            throw AssistantError.message("请选择 1 至 256 个本地文件或文件夹。")
        }
        var seen = Set<URL>()
        self.urls = urls.map { $0.standardizedFileURL }.filter { seen.insert($0).inserted }
        let first = self.urls[0]
        let isDirectory = (try? first.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]))
        let chosenDirectory = directory ?? (isDirectory?.isDirectory == true && isDirectory?.isPackage != true
            ? first : first.deletingLastPathComponent())
        self.directory = URL(fileURLWithPath: chosenDirectory.path, isDirectory: true).standardizedFileURL
    }
}

enum Handoff {
    static let scheme = "rightclick-assistant"
    static func url(action: MenuAction, selection: Selection?, background: Bool = false, options: ActionOptions = ActionOptions()) -> URL {
        var c = URLComponents()
        c.scheme = scheme; c.host = "action"; c.path = "/" + action.rawValue
        c.queryItems = selection.map {
            [URLQueryItem(name: "directory", value: $0.directory.path)] +
                $0.urls.map { URLQueryItem(name: "item", value: $0.path) }
        } ?? []
        if background { c.queryItems!.append(URLQueryItem(name: "background", value: "1")) }
        for (key, value) in [("destination", options.destination), ("template", options.template), ("application", options.application), ("icon", options.icon)] {
            if let value { c.queryItems!.append(URLQueryItem(name: key, value: value)) }
        }
        return c.url!
    }
    static func isBackground(_ url: URL) -> Bool {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains(URLQueryItem(name: "background", value: "1")) == true
    }
    static func decode(_ url: URL) throws -> (MenuAction, Selection?, ActionOptions) {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              c.scheme == scheme, c.host == "action", c.user == nil, c.password == nil,
              c.port == nil, c.fragment == nil,
              let a = MenuAction(rawValue: String(c.path.dropFirst())) else {
            throw AssistantError.message("无法识别这个右键操作。")
        }
        let items = c.queryItems ?? []
        guard items.allSatisfy({ ["item", "directory", "background", "destination", "template", "application", "icon"].contains($0.name) }),
              items.filter({ $0.name == "directory" }).count <= 1,
              items.filter({ $0.name == "background" }).count <= 1,
              items.filter({ $0.name == "background" }).allSatisfy({ $0.value == "1" }) else {
            throw AssistantError.message("右键操作参数无效。")
        }
        let paths = items.filter { $0.name == "item" }.compactMap(\.value)
        let directory = items.first { $0.name == "directory" }?.value
        guard paths.allSatisfy({ $0.hasPrefix("/") && !$0.contains("\0") }),
              directory == nil || (directory!.hasPrefix("/") && !directory!.contains("\0")) else {
            throw AssistantError.message("右键操作需要绝对文件路径。")
        }
        let selection = paths.isEmpty ? nil : try Selection(urls: paths.map { URL(fileURLWithPath: $0) },
                                                          directory: directory.map { URL(fileURLWithPath: $0) })
        if a != .settings && selection == nil { throw AssistantError.message("没有选中的文件。") }
        let optionNames = ["destination", "template", "application", "icon"]
        guard optionNames.allSatisfy({ key in items.filter { $0.name == key }.count <= 1 }) else {
            throw AssistantError.message("右键操作参数重复。")
        }
        let options = ActionOptions(destination: items.first { $0.name == "destination" }?.value,
                                    template: items.first { $0.name == "template" }?.value,
                                    application: items.first { $0.name == "application" }?.value,
                                    icon: items.first { $0.name == "icon" }?.value)
        try options.validate(action: a)
        return (a, selection, options)
    }
}

struct ActionOptions {
    var destination: String? = nil
    var template: String? = nil
    var application: String? = nil
    var icon: String? = nil
    func validate(action: MenuAction) throws {
        guard [destination, application].compactMap({ $0 }).allSatisfy({ $0.hasPrefix("/") && !$0.contains("\0") }),
              destination == nil || [.copyTo, .moveTo].contains(action),
              template == nil || action == .newTemplate,
              application == nil || action == .otherApp,
              icon == nil || (action == .setIcon && IconPreset.all.contains { $0.symbol == icon }) else {
            throw AssistantError.message("子菜单参数与操作不匹配。")
        }
        if let template, !TemplatePolicy.validID(template) {
            throw AssistantError.message("模板标识无效。")
        }
    }
}

struct IconPreset {
    let name: String
    // Keep the existing handoff identifiers; they no longer select SF Symbols.
    let symbol: String
    let typeIdentifier: String
    static let all: [IconPreset] = [
        IconPreset(name: "文件夹", symbol: "folder.fill", typeIdentifier: "public.folder"),
        IconPreset(name: "文稿", symbol: "doc.text.fill", typeIdentifier: "com.apple.documents-folder"),
        IconPreset(name: "应用", symbol: "app.fill", typeIdentifier: "com.apple.applications-folder"),
        IconPreset(name: "图片", symbol: "photo.fill", typeIdentifier: "com.apple.pictures-folder"),
        IconPreset(name: "音乐", symbol: "music.note", typeIdentifier: "com.apple.music-folder"),
        IconPreset(name: "视频", symbol: "film.fill", typeIdentifier: "com.apple.movie-folder"),
        IconPreset(name: "资源库", symbol: "book.fill", typeIdentifier: "com.apple.library-folder"),
        IconPreset(name: "代码", symbol: "curlybraces", typeIdentifier: "com.apple.developer-folder")
    ]
}

struct FolderReference: Codable, Equatable { var name: String; var path: String }

/// One settings row is also one Finder menu choice; order is the stored array order.
struct TemplateReference: Codable, Equatable {
    var id: String
    var name: String
    var filename: String
    var sourcePath: String?
    var enabled: Bool
    var showInMainMenu: Bool

    static let defaults: [TemplateReference] = [
        ("txt", "TXT", "TXT.txt", true),
        ("markdown", "Markdown", "Markdown.md", true),
        ("rtf", "RTF", "RTF.rtf", true),
        ("xml", "XML", "XML.xml", true),
        ("word", "Word", "Word.docx", true),
        ("excel", "Excel", "Excel.xlsx", true),
        ("ppt", "PPT", "PowerPoint.pptx", true),
        ("json", "JSON", "JSON.json", false),
        ("html", "HTML", "HTML.html", false),
        ("python", "Python", "Python.py", false),
        ("swift", "Swift", "Swift.swift", false)
    ].map { TemplateReference(id: "builtin-" + $0.0, name: $0.1, filename: $0.2,
                              sourcePath: nil, enabled: $0.3, showInMainMenu: false) }

    static func legacyCustom(path: String, enabled: Bool) -> TemplateReference {
        // Deterministic across the host and Finder extension, unlike Swift hashValue.
        let hash = path.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
        let filename = URL(fileURLWithPath: path).lastPathComponent
        return TemplateReference(id: "custom-" + String(hash, radix: 16),
                                 name: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
                                 filename: filename, sourcePath: path, enabled: enabled, showInMainMenu: false)
    }
}

enum TemplatePolicy {
    static func validID(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.count <= 128 && id.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45
        }
    }

    static func sourceURL(for reference: TemplateReference, resources: URL) throws -> URL {
        guard validID(reference.id) else { throw AssistantError.message("模板标识无效。") }
        try FilePolicy.validateName(reference.filename)
        let source: URL
        if let path = reference.sourcePath {
            guard path.hasPrefix("/"), !path.contains("\0") else {
                throw AssistantError.message("模板需要本地绝对路径。")
            }
            source = URL(fileURLWithPath: path).standardizedFileURL
            guard source.lastPathComponent == reference.filename else {
                throw AssistantError.message("模板文件名与来源不一致，请重新添加模板。")
            }
        } else {
            guard TemplateReference.defaults.contains(where: { $0.id == reference.id && $0.filename == reference.filename }) else {
                throw AssistantError.message("这个内置模板不存在。")
            }
            source = resources.appendingPathComponent("Templates", isDirectory: true).appendingPathComponent(reference.filename)
        }
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw AssistantError.message("模板必须是一个文件。") }
        if (values.fileSize ?? 0) == 0 && !emptyFileAllowed(extension: source.pathExtension) {
            throw AssistantError.message("这个格式需要有效模板，不能使用空白文件。")
        }
        return source
    }

    static func filename(for reference: TemplateReference, proposedName: String) throws -> String {
        try FilePolicy.validateName(reference.filename)
        try FilePolicy.validateName(proposedName)
        let suffix = URL(fileURLWithPath: reference.filename).pathExtension
        guard !suffix.isEmpty else { return proposedName }
        if URL(fileURLWithPath: proposedName).pathExtension.caseInsensitiveCompare(suffix) == .orderedSame {
            return proposedName
        }
        return proposedName + "." + suffix
    }

    static func emptyFileAllowed(extension suffix: String) -> Bool {
        // An empty byte stream is meaningful only for unstructured/text file types.
        let structured = ["doc", "docx", "xls", "xlsx", "ppt", "pptx", "wps", "et", "dps", "pages", "numbers", "key",
                          "rtf", "pdf", "psd", "ai", "png", "jpg", "jpeg", "gif", "heic", "heif", "tif", "tiff",
                          "webp", "icns", "ico", "avif", "bmp", "zip", "7z", "rar", "gz", "bz2", "xz", "tar"]
        return !structured.contains(suffix.lowercased())
    }

    static func create(_ reference: TemplateReference, name: String, in directory: URL, resources: URL) throws -> URL {
        guard reference.enabled else { throw AssistantError.message("这个模板已停用。") }
        guard directory.isFileURL, MenuPolicy.isFolder(directory) else {
            throw AssistantError.message("请选择创建文件的文件夹。")
        }
        let source = try sourceURL(for: reference, resources: resources)
        let target = directory.appendingPathComponent(try filename(for: reference, proposedName: name))
        let staging = directory.appendingPathComponent(".rightclick-template-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.copyItem(at: source, to: staging)
        // Same-directory commit: visible only once complete, and RENAME_EXCL never replaces another file.
        guard renameatx_np(AT_FDCWD, staging.path, AT_FDCWD, target.path, UInt32(RENAME_EXCL)) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: target.path])
        }
        return target
    }
}

struct AppReference: Codable, Equatable {
    var name: String
    var path: String
    var enabled = true

    init(name: String, path: String, enabled: Bool = true) {
        self.name = name; self.path = path; self.enabled = enabled
    }
    private enum CodingKeys: String, CodingKey { case name, path, enabled }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        path = try c.decode(String.self, forKey: .path)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}

struct AssistantConfiguration: Codable {
    var applications: [AppReference] = []
    var commonFolders: [String] = []
    var customTemplates: [String] = []
    var newFileTemplates: [TemplateReference] = TemplateReference.defaults
    var customNewFileEnabled = true
    var customNewFileMainMenu = false
    var customNewFileName = "自定义创建新文件"
    var newFileShowIcons = true
    var newFileSound = true
    var newFileAutoOpen = false
    var destinationFolders: [FolderReference] = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [("下载", "Downloads"), ("桌面", "Desktop"), ("文稿", "Documents"), ("图片", "Pictures"), ("音乐", "Music"), ("影片", "Movies")].map {
            FolderReference(name: $0.0, path: home.appendingPathComponent($0.1).path)
        }
    }()
    var disabledActions: Set<String> = []
    var showIcons = true
    var mergeMenus = true
    init() {}
    enum CodingKeys: String, CodingKey {
        case applications, commonFolders, customTemplates, destinationFolders, disabledActions, showIcons, mergeMenus
        case newFileTemplates, customNewFileEnabled, customNewFileMainMenu, customNewFileName, newFileShowIcons, newFileSound, newFileAutoOpen
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        applications = try c.decodeIfPresent([AppReference].self, forKey: .applications) ?? []
        commonFolders = try c.decodeIfPresent([String].self, forKey: .commonFolders) ?? []
        customTemplates = try c.decodeIfPresent([String].self, forKey: .customTemplates) ?? []
        destinationFolders = try c.decodeIfPresent([FolderReference].self, forKey: .destinationFolders) ?? destinationFolders
        disabledActions = try c.decodeIfPresent(Set<String>.self, forKey: .disabledActions) ?? []
        disabledActions.subtract(["chatGPT", "analyze"])
        showIcons = try c.decodeIfPresent(Bool.self, forKey: .showIcons) ?? true
        mergeMenus = try c.decodeIfPresent(Bool.self, forKey: .mergeMenus) ?? true
        if let templates = try c.decodeIfPresent([TemplateReference].self, forKey: .newFileTemplates) {
            newFileTemplates = templates
        } else {
            let templateDisabled = disabledActions.contains(MenuAction.newTemplate.rawValue)
            newFileTemplates = TemplateReference.defaults.map { reference in
                var migrated = reference
                if reference.id == "builtin-txt" { migrated.enabled = !disabledActions.contains(MenuAction.newText.rawValue) }
                else if reference.id == "builtin-markdown" { migrated.enabled = !disabledActions.contains(MenuAction.newMarkdown.rawValue) }
                else if templateDisabled { migrated.enabled = false }
                return migrated
            }
            var paths = Set<String>()
            newFileTemplates += customTemplates.filter { $0.hasPrefix("/") && !$0.contains("\0") && paths.insert($0).inserted }
                .map { TemplateReference.legacyCustom(path: $0, enabled: !templateDisabled) }
        }
        disabledActions.subtract([MenuAction.newText.rawValue, MenuAction.newMarkdown.rawValue, MenuAction.newTemplate.rawValue])
        customNewFileEnabled = try c.decodeIfPresent(Bool.self, forKey: .customNewFileEnabled) ?? true
        customNewFileMainMenu = try c.decodeIfPresent(Bool.self, forKey: .customNewFileMainMenu) ?? false
        customNewFileName = try c.decodeIfPresent(String.self, forKey: .customNewFileName) ?? "自定义创建新文件"
        newFileShowIcons = try c.decodeIfPresent(Bool.self, forKey: .newFileShowIcons) ?? true
        newFileSound = try c.decodeIfPresent(Bool.self, forKey: .newFileSound) ?? true
        newFileAutoOpen = try c.decodeIfPresent(Bool.self, forKey: .newFileAutoOpen) ?? false
    }
    static let preferenceDomain = "local.kingdee.RightClickAssistant.preferences"
    static let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/RightClickAssistant", isDirectory: true)
    static var file: URL { root.appendingPathComponent("configuration.json") }
    static func load() -> Self {
        if let data = UserDefaults(suiteName: preferenceDomain)?.data(forKey: "configuration"),
           let value = try? JSONDecoder().decode(Self.self, from: data) { return value }
        return (try? JSONDecoder().decode(Self.self, from: Data(contentsOf: file))) ?? Self()
    }
    func save() throws {
        try FileManager.default.createDirectory(at: Self.root, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(self)
        try data.write(to: Self.file, options: .atomic)
        let defaults = UserDefaults(suiteName: Self.preferenceDomain)
        defaults?.set(data, forKey: "configuration"); defaults?.synchronize()
    }
    func enabled(_ action: MenuAction) -> Bool { action == .settings || !disabledActions.contains(action.rawValue) }
}

enum FilePolicy {
    static func validateName(_ name: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name != ".", name != "..", !name.contains("/"), !name.contains("\0") else {
            throw AssistantError.message("名称不能为空，也不能包含 /。")
        }
    }
    static func uniqueURL(in directory: URL, name: String) -> URL {
        let original = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: original.path) else { return original }
        let ext = original.pathExtension
        let stem = original.deletingPathExtension().lastPathComponent
        var count = 2
        while true {
            let u = directory.appendingPathComponent(stem + " \(count)" + (ext.isEmpty ? "" : "." + ext))
            if !FileManager.default.fileExists(atPath: u.path) { return u }; count += 1
        }
    }
    static func transfer(_ urls: [URL], to directory: URL, move: Bool) -> [String] {
        var errors: [String] = []
        for source in urls {
            let destination = directory.appendingPathComponent(source.lastPathComponent)
            do {
                guard source.standardizedFileURL != destination.standardizedFileURL else { continue }
                let resolvedSource = source.resolvingSymlinksInPath().path
                let resolvedDestination = destination.resolvingSymlinksInPath().path
                guard !resolvedDestination.hasPrefix(resolvedSource + "/") else {
                    throw AssistantError.message("不能把文件夹复制或移动到自身内部。")
                }
                if move { try FileManager.default.moveItem(at: source, to: destination) }
                else { try FileManager.default.copyItem(at: source, to: destination) }
            } catch { errors.append("\(source.lastPathComponent)：\(error.localizedDescription)") }
        }
        return errors
    }
}

/// Admits only ordinary classic ZIP entries before invoking the OS extractor.
enum ZIPPolicy {
    static func validate(_ data: Data) throws -> UInt64 {
        let b = data
        func u16(_ p: Int) -> UInt16 { UInt16(b[p]) | UInt16(b[p+1]) << 8 }
        func u32(_ p: Int) -> UInt32 { UInt32(u16(p)) | UInt32(u16(p+2)) << 16 }
        guard b.count >= 22 else { throw AssistantError.message("ZIP 文件不完整。") }
        let lower = max(0, b.count - 65_557)
        guard let end = stride(from: b.count - 22, through: lower, by: -1).first(where: {
            u32($0) == 0x06054b50 && $0 + 22 + Int(u16($0+20)) == b.count
        }) else { throw AssistantError.message("无法读取 ZIP 目录。") }
        let entries = Int(u16(end+10)), start = Int(u32(end+16)), size = Int(u32(end+12))
        guard u16(end+4) == 0, u16(end+6) == 0, u16(end+8) == u16(end+10),
              entries != 65_535, start <= end, size <= end - start else {
            throw AssistantError.message("分卷或 ZIP64 归档请使用 Keka 解压。")
        }
        var position = start; var bytes: UInt64 = 0
        func validateExtra(_ lower: Int, _ upper: Int) throws {
            var p = lower
            while p < upper {
                guard p + 4 <= upper else { throw AssistantError.message("ZIP 扩展字段损坏。") }
                let id = u16(p), length = Int(u16(p+2)); p += 4
                guard p + length <= upper, [UInt16(0x5455), 0x7875, 0x5855, 0x000a].contains(id) else {
                    throw AssistantError.message("这个 ZIP 包含未支持的扩展元数据，请使用 Keka 检查后解压。")
                }
                p += length
            }
        }
        for _ in 0..<entries {
            guard position + 46 <= start + size, u32(position) == 0x02014b50 else {
                throw AssistantError.message("ZIP 目录损坏。")
            }
            let length = Int(u16(position+28)), extra = Int(u16(position+30)), comment = Int(u16(position+32))
            let next = position + 46 + length + extra + comment
            guard next <= start + size else { throw AssistantError.message("ZIP 文件名超出目录范围。") }
            let name = String(decoding: b[(position+46)..<(position+46+length)], as: UTF8.self)
            let parts = name.replacingOccurrences(of: "\\", with: "/").split(separator: "/")
            let mode = u32(position+38) >> 16
            guard !name.isEmpty, !name.hasPrefix("/"), !name.hasPrefix("\\"),
                  !name.contains("\0"), !parts.contains(".."),
                  !(parts.first?.contains(":") ?? false), [UInt32(0), 0x8000, 0x4000].contains(mode & 0xf000),
                  u16(position+8) & 1 == 0, u32(position+24) != UInt32.max else {
                throw AssistantError.message("归档包含越界路径、符号链接或加密项目；请使用 Keka 检查后解压。")
            }
            let local = Int(u32(position+42))
            guard local + 30 <= start, u32(local) == 0x04034b50,
                  u16(local+6) == u16(position+8), u16(local+8) == u16(position+10) else {
                throw AssistantError.message("ZIP 的本地记录与目录不一致。")
            }
            let localName = Int(u16(local+26)), localExtra = Int(u16(local+28))
            let payload = local + 30 + localName + localExtra
            guard payload <= start, UInt64(payload) + UInt64(u32(position+20)) <= UInt64(start),
                  data[(local+30)..<(local+30+localName)] == data[(position+46)..<(position+46+length)] else {
                throw AssistantError.message("ZIP 的文件名或数据范围不一致。")
            }
            try validateExtra(local+30+localName, payload)
            try validateExtra(position+46+length, position+46+length+extra)
            bytes += UInt64(u32(position+24)); position = next
        }
        guard position == start + size else { throw AssistantError.message("ZIP 目录存在未识别内容。") }
        return bytes
    }
}
