import Foundation
import AppKit
import ImageIO

@main struct Checks {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        var checks: [String] = []
        func check(_ name: String, _ condition: @autoclosure () throws -> Bool) throws {
            guard try condition() else { throw AssistantError.message("FAIL: " + name) }; checks.append(name)
            FileHandle.standardOutput.write(Data(("PASS: " + name + "\n").utf8))
        }
        func rejects(_ name: String, _ operation: () throws -> Void) throws {
            do { try operation() } catch { checks.append(name); return }
            throw AssistantError.message("FAIL: expected rejection: " + name)
        }
        let folder = root.appendingPathComponent("文件夹 #&?%+ 你好")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("资料 #&?%+;$(literal).txt")
        try Data("round trip".utf8).write(to: file)
        let selection = try Selection(urls: [file, file], directory: folder)
        try check("Finder menu tags resolve without representedObject", MenuAction.allCases.allSatisfy { MenuAction(menuTag: $0.menuTag) == $0 })
        try check("Finder menu rejects separator tag", MenuAction(menuTag: 0) == nil)
        try check("selected folder is the working directory", try Selection(urls: [folder]).directory.path == folder.path)
        try check("selected file uses its containing directory", try Selection(urls: [file]).directory.path == folder.path)
        try check("background offers creation", MenuPolicy.allows(.newText, selected: []))
        try check("background does not delete current directory", !MenuPolicy.allows(.deleteForever, selected: []))
        try check("background hides selection copy commands", !MenuPolicy.allows(.copyPath, selected: []) && !MenuPolicy.allows(.copyTo, selected: []))
        try check("background hides terminal", !MenuPolicy.allows(.terminal, selected: []))
        try check("regular file hides terminal", !MenuPolicy.allows(.terminal, selected: [file]))
        try check("folder permits terminal", MenuPolicy.allows(.terminal, selected: [folder]))
        try check("mixed selection hides terminal", !MenuPolicy.allows(.terminal, selected: [folder, file]))
        try check("file selection offers copy and delete", MenuPolicy.allows(.copyPath, selected: [file]) && MenuPolicy.allows(.deleteForever, selected: [file]))
        try check("text file hides image operations", !MenuPolicy.allows(.png, selected: [file]))
        try check("image offers conversion", MenuPolicy.allows(.jpeg, selected: [URL(fileURLWithPath: "/tmp/example.png")]))
        try check("archive offers extract", MenuPolicy.allows(.extract, selected: [URL(fileURLWithPath: "/tmp/example.zip")]))
        try check("background context survives handoff", Handoff.isBackground(Handoff.url(action: .newText, selection: selection, background: true)))
        let legacyConfiguration = try JSONDecoder().decode(AssistantConfiguration.self, from: Data("{\"commonFolders\":[\"/tmp\"]}".utf8))
        try check("settings migration preserves favorites", legacyConfiguration.commonFolders == ["/tmp"] && legacyConfiguration.showIcons)
        try check("selection deduplicates", selection.urls.count == 1)
        let decoded = try Handoff.decode(Handoff.url(action: .chatGPT, selection: selection))
        try check("Unicode and reserved characters round-trip", decoded.0 == .chatGPT && decoded.1 == selection)
        let destinationOptions = try Handoff.decode(Handoff.url(action: .copyTo, selection: selection, options: ActionOptions(destination: folder.path)))
        try check("submenu destination survives handoff", destinationOptions.2.destination == folder.path)
        let templateOptions = try Handoff.decode(Handoff.url(action: .newTemplate, selection: selection, options: ActionOptions(template: "builtin-word")))
        try check("submenu template identity survives handoff", templateOptions.2.template == "builtin-word")
        let iconOptions = try Handoff.decode(Handoff.url(action: .setIcon, selection: selection, options: ActionOptions(icon: "folder.fill")))
        try check("submenu icon survives handoff", iconOptions.2.icon == "folder.fill")
        try check("legacy settings gain standard destinations", legacyConfiguration.destinationFolders.count == 6 && legacyConfiguration.destinationFolders.allSatisfy { $0.path.hasPrefix("/") })
        try rejects("destination cannot change unrelated action") { _ = try Handoff.decode(Handoff.url(action: .deleteForever, selection: selection, options: ActionOptions(destination: folder.path))) }
        try rejects("template cannot traverse directories") { _ = try Handoff.decode(Handoff.url(action: .newTemplate, selection: selection, options: ActionOptions(template: "../secret"))) }
        try rejects("template file path cannot be used as identity") { _ = try Handoff.decode(Handoff.url(action: .newTemplate, selection: selection, options: ActionOptions(template: "Word.docx"))) }
        try rejects("unknown icon is rejected") { _ = try Handoff.decode(Handoff.url(action: .setIcon, selection: selection, options: ActionOptions(icon: "unknown"))) }
        try rejects("duplicate destinations are rejected") { _ = try Handoff.decode(URL(string: "rightclick-assistant://action/copyTo?item=/tmp/x&destination=/tmp&destination=/")!) }
        try rejects("empty selection") { _ = try Selection(urls: []) }
        try rejects("unknown handoff action") { _ = try Handoff.decode(URL(string: "rightclick-assistant://action/execute?item=/tmp/x")!) }
        try rejects("relative path") { _ = try Handoff.decode(URL(string: "rightclick-assistant://action/chatGPT?item=relative")!) }
        try rejects("ambiguous directory") { _ = try Handoff.decode(URL(string: "rightclick-assistant://action/chatGPT?item=/tmp/x&directory=/tmp&directory=/")!) }
        try rejects("remote source") { _ = try Selection(urls: [URL(string: "https://example.com/x")!]) }
        try rejects("filename traversal") { try FilePolicy.validateName("../x") }
        let link = ChatGPTLink.draft(selection: selection, instruction: "分析 #&?%+ 中文")
        let query = URLComponents(url: link, resolvingAgainstBaseURL: false)!.queryItems!
        try check("documented local workspace in draft", query.first { $0.name == "path" }!.value == folder.path)
        try check("draft retains full selected path and text", query.first { $0.name == "prompt" }!.value!.contains(file.path))
        try check("draft has no automatic-send flag", Set(query.map(\.name)) == ["path", "prompt"])
        let folderLink = URLComponents(url: ChatGPTLink.folder(folder), resolvingAgainstBaseURL: false)!
        try check("folder opens workspace without fabricated prompt", folderLink.queryItems == [URLQueryItem(name: "path", value: folder.path)])

        let source = root.appendingPathComponent("source"), destination = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let first = source.appendingPathComponent("first.txt"), second = source.appendingPathComponent("second.txt")
        try Data("original".utf8).write(to: first); try Data("second".utf8).write(to: second)
        let collision = destination.appendingPathComponent("first.txt"); try Data("keep".utf8).write(to: collision)
        let errors = FilePolicy.transfer([first, second], to: destination, move: true)
        try check("batch move reports conflict", errors.count == 1)
        try check("conflict leaves source intact", try String(contentsOf: first, encoding: .utf8) == "original")
        try check("conflict preserves destination", try String(contentsOf: collision, encoding: .utf8) == "keep")
        try check("nonconflicting item still moves", FileManager.default.fileExists(atPath: destination.appendingPathComponent("second.txt").path) && !FileManager.default.fileExists(atPath: second.path))
        let nested = source.appendingPathComponent("nested"); try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
        try check("rejects recursive copy into source", !FilePolicy.transfer([source], to: nested, move: false).isEmpty)

        try check("custom creation follows blank and folder context", MenuPolicy.allows(.newEmpty, selected: []) && MenuPolicy.allows(.newEmpty, selected: [folder]) && !MenuPolicy.allows(.newEmpty, selected: [file]))
        try check("template defaults have stable unique identities", TemplateReference.defaults.count == 11 && Set(TemplateReference.defaults.map(\.id)).count == 11 && TemplateReference.defaults.allSatisfy { TemplatePolicy.validID($0.id) })
        try check("structured formats never allow empty creation", ["docx", "xlsx", "pptx", "wps", "pages", "png", "zip"].allSatisfy { !TemplatePolicy.emptyFileAllowed(extension: $0) } && TemplatePolicy.emptyFileAllowed(extension: "txt"))
        let oldTemplateConfiguration = try JSONDecoder().decode(AssistantConfiguration.self, from: Data("{\"customTemplates\":[\"/tmp/会议模板.docx\",\"/tmp/会议模板.docx\"],\"disabledActions\":[\"newText\",\"newTemplate\",\"terminal\"]}".utf8))
        try check("legacy template switches migrate into individual rows", oldTemplateConfiguration.newFileTemplates.first { $0.id == "builtin-txt" }?.enabled == false && oldTemplateConfiguration.newFileTemplates.first { $0.id == "builtin-markdown" }?.enabled == true && oldTemplateConfiguration.newFileTemplates.first { $0.id == "builtin-word" }?.enabled == false)
        try check("legacy master switches no longer hide all templates", oldTemplateConfiguration.enabled(.newTemplate) && oldTemplateConfiguration.enabled(.newText) && !oldTemplateConfiguration.enabled(.terminal))
        try check("legacy custom template migration deduplicates and preserves source", oldTemplateConfiguration.newFileTemplates.filter { $0.sourcePath != nil }.count == 1 && oldTemplateConfiguration.newFileTemplates.last?.sourcePath == "/tmp/会议模板.docx" && oldTemplateConfiguration.newFileTemplates.last?.enabled == false)
        let migratedAgain = try JSONDecoder().decode(AssistantConfiguration.self, from: Data("{\"customTemplates\":[\"/tmp/会议模板.docx\"],\"disabledActions\":[\"newTemplate\"]}".utf8))
        try check("legacy custom template identities match across processes", oldTemplateConfiguration.newFileTemplates.last?.id == migratedAgain.newFileTemplates.last?.id)
        var edited = AssistantConfiguration()
        edited.newFileTemplates.reverse()
        edited.newFileTemplates[0].name = "项目 Swift 模板"
        edited.newFileTemplates[0].enabled = true
        edited.newFileTemplates[0].showInMainMenu = true
        edited.newFileTemplates[1].enabled = false
        edited.customNewFileName = "创建空白文件"
        edited.customNewFileMainMenu = true
        edited.newFileShowIcons = false; edited.newFileSound = false; edited.newFileAutoOpen = true
        let settingsSnapshot = root.appendingPathComponent("template-settings.json")
        try JSONEncoder().encode(edited).write(to: settingsSnapshot, options: .atomic)
        let extensionConfiguration = try JSONDecoder().decode(AssistantConfiguration.self, from: Data(contentsOf: settingsSnapshot))
        try check("saved template rename order and menu placement are shared", extensionConfiguration.newFileTemplates == edited.newFileTemplates && extensionConfiguration.newFileTemplates[0].name == "项目 Swift 模板" && extensionConfiguration.newFileTemplates[0].showInMainMenu)
        try check("saved disabled row stays absent from enabled choices", !extensionConfiguration.newFileTemplates.filter(\.enabled).contains { $0.id == edited.newFileTemplates[1].id })
        try check("new file options round-trip independently", !extensionConfiguration.newFileShowIcons && !extensionConfiguration.newFileSound && extensionConfiguration.newFileAutoOpen && extensionConfiguration.customNewFileMainMenu && extensionConfiguration.customNewFileName == "创建空白文件")
        let resources = root.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources", isDirectory: true)
        let word = TemplateReference.defaults.first { $0.id == "builtin-word" }!
        try check("template supplies its correct extension", try TemplatePolicy.filename(for: word, proposedName: "会议记录") == "会议记录.docx" && TemplatePolicy.filename(for: word, proposedName: "会议记录.DOCX") == "会议记录.DOCX")
        let newDocument = try TemplatePolicy.create(word, name: "真实 Word #& 中文", in: folder, resources: resources)
        try check("new Word copies the complete valid template", try Data(contentsOf: newDocument) == Data(contentsOf: TemplatePolicy.sourceURL(for: word, resources: resources)) && Data(contentsOf: newDocument).count > 0)
        try rejects("new template refuses to replace an existing file") { _ = try TemplatePolicy.create(word, name: "真实 Word #& 中文", in: folder, resources: resources) }
        try check("failed template commit leaves existing file intact", try Data(contentsOf: newDocument) == Data(contentsOf: TemplatePolicy.sourceURL(for: word, resources: resources)))
        try check("template staging files are removed after commit or failure", try !FileManager.default.contentsOfDirectory(atPath: folder.path).contains { $0.hasPrefix(".rightclick-template-") })
        try rejects("new template rejects traversal name") { _ = try TemplatePolicy.create(word, name: "../outside", in: folder, resources: resources) }
        var disabledWord = word; disabledWord.enabled = false
        try rejects("disabled template cannot execute through handoff") { _ = try TemplatePolicy.create(disabledWord, name: "disabled", in: folder, resources: resources) }
        let emptyOffice = source.appendingPathComponent("bad.docx"); try Data().write(to: emptyOffice)
        let badTemplate = TemplateReference(id: "custom-test", name: "坏模板", filename: "bad.docx", sourcePath: emptyOffice.path, enabled: true, showInMainMenu: false)
        try rejects("empty Office source is rejected") { _ = try TemplatePolicy.create(badTemplate, name: "should-not-exist", in: folder, resources: resources) }
        let emptyText = source.appendingPathComponent("custom.txt"); try Data().write(to: emptyText)
        var customText = badTemplate; customText.filename = "custom.txt"; customText.sourcePath = emptyText.path
        let emptyTextOutput = try TemplatePolicy.create(customText, name: "空文本", in: folder, resources: resources)
        try check("empty text template creates a valid empty text file", try Data(contentsOf: emptyTextOutput).isEmpty && emptyTextOutput.pathExtension == "txt")
        var missingTemplate = customText; missingTemplate.sourcePath = source.appendingPathComponent("missing.txt").path; missingTemplate.filename = "missing.txt"
        try rejects("missing template fails instead of creating a fake file") { _ = try TemplatePolicy.create(missingTemplate, name: "missing", in: folder, resources: resources) }

        for name in ["traversal", "symlink", "local-mismatch", "invalid-offset"] {
            try rejects("ZIP rejects " + name) { _ = try ZIPPolicy.validate(Data(contentsOf: root.appendingPathComponent(name + ".zip"))) }
        }
        try check("ZIP accepts ordinary entry", try ZIPPolicy.validate(Data(contentsOf: root.appendingPathComponent("safe.zip"))) == 12)
        let out = try CommandWork.extractZIP(root.appendingPathComponent("safe.zip"))
        try check("ZIP extracts to fresh folder", try String(contentsOf: out.appendingPathComponent("nested/safe.txt"), encoding: .utf8) == "safe content")
        let zip = root.appendingPathComponent("输出 #& 中文.zip")
        try CommandWork.compress([first, collision], to: zip, seven: false)
        _ = try ZIPPolicy.validate(Data(contentsOf: zip))
        let roundTrip = try CommandWork.extractZIP(zip)
        try check("ZIP duplicate basenames preserved", FileManager.default.fileExists(atPath: roundTrip.appendingPathComponent("first.txt").path) && FileManager.default.fileExists(atPath: roundTrip.appendingPathComponent("first 2.txt").path))
        if CommandWork.sevenZip != nil {
            let seven = root.appendingPathComponent("test.7z")
            try CommandWork.compress([first], to: seven, seven: true)
            let list = try CommandWork.run(CommandWork.sevenZip!, ["t", seven.path])
            try check("7z archive engine round-trip integrity", list.contains("Everything is Ok"))
        }

        let ctx = CGContext(data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 64*4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(NSColor.systemGreen.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
        let png = root.appendingPathComponent("input.png"); try MediaWork.encode(ctx.makeImage()!, type: "public.png", to: png)
        try rejects("image export refuses overwrite") { try MediaWork.encode(ctx.makeImage()!, type: "public.png", to: png) }
        let converted = try MediaWork.convert(png, action: .jpeg)
        try check("JPEG decodes at original dimensions", try MediaWork.image(converted).width == 64)
        let mac = try MediaWork.iconSet(png, ios: false)
        try check("Mac icon set has all sizes", try FileManager.default.contentsOfDirectory(atPath: mac.path).count == 10)
        let ios = try MediaWork.iconSet(png, ios: true)
        let contents = try JSONSerialization.jsonObject(with: Data(contentsOf: ios.appendingPathComponent("Contents.json"))) as! [String: Any]
        try check("iOS icon set metadata", (contents["images"] as? [[String:String]])?.count == 18)
        try check("QR generation", try MediaWork.qr("测试 QR #&中文").size.width > 0)
        let result: [String: Any] = ["passed": checks.count, "checks": checks, "failed": 0]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: root.deletingLastPathComponent().appendingPathComponent("check-results.json"))
        print(String(decoding: data, as: UTF8.self))
    }
}
