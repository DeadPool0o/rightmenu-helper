import AppKit
import FinderSync
import ServiceManagement

final class ScrollDocument: NSView {
    override var isFlipped: Bool { true }
}

final class AppController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var configuration = AssistantConfiguration.load()
    var sharingPicker: NSSharingServicePicker?
    private let statusLabel = NSTextField(labelWithString: "就绪")
    private var settingsView: SettingsView!
    private var window: NSWindow!
    private var statusItem: NSStatusItem!
    private var busy = false
    private var receivedHandoff = false
    private var ready = false
    private var pending: [(MenuAction, Selection?, ActionOptions)] = []
    lazy var runner = ActionRunner(self)

    func applicationDidFinishLaunching(_ notification: Notification) {
        ActionLog.record("host ready " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"))
        NSApp.servicesProvider = self
        do { try configuration.save() } catch { ActionLog.record("settings initialization failed=" + error.localizedDescription) }
        buildWindow(); buildStatusMenu(); ready = true
        let queued = pending; pending.removeAll()
        for (action, selection, options) in queued { runner.execute(action, selection: selection, options: options) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            if !self.receivedHandoff { self.showWindow() }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow(); return false
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        receivedHandoff = true
        for url in urls {
            do {
                let (action, received, options) = try Handoff.decode(url)
                // Resolve directory metadata in the containing app, outside the Finder extension's sandbox.
                let selection = try received.map { try Selection(urls: $0.urls) }
                guard MenuPolicy.allows(action, selected: Handoff.isBackground(url) ? [] : selection?.urls ?? []) else {
                    throw AssistantError.message("此操作不适用于当前选择。请重新右键选择相应的文件或文件夹。")
                }
                ActionLog.record("received action=" + action.rawValue + " selectionCount=" + String(selection?.urls.count ?? 0))
                if ready { runner.execute(action, selection: selection, options: options) }
                else { pending.append((action, selection, options)) }
            } catch { self.error(error) }
        }
    }
    func status(_ text: String) { statusLabel.stringValue = text }
    func error(_ error: Error) {
        NSLog("RightClickAssistant action error: %@", error.localizedDescription)
        message("操作未完成", error.localizedDescription); status("操作未完成")
    }
    func message(_ title: String, _ detail: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = detail
        alert.addButton(withTitle: "好"); alert.runModal()
    }
    func showWindow() {
        guard window != nil else { return }
        NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
    }
    func share(_ urls: [URL]) {
        let picker = NSSharingServicePicker(items: urls); sharingPicker = picker
        if let button = statusItem.button {
            picker.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
    func work(_ title: String, body: @escaping () throws -> String) {
        guard !busy else { message("正在处理", "请等待当前操作完成。"); return }
        busy = true; status(title + "…")
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try body() }
            DispatchQueue.main.async {
                self.busy = false
                switch result {
                case .success(let text): self.status(text)
                case .failure(let error): self.error(error)
                }
            }
        }
    }
    @objc private func showSettings() { showWindow() }
    @objc private func quit() { NSApp.terminate(nil) }
    func persistSettings() {
        do { try configuration.save(); status("设置已保存") } catch { self.error(error) }
    }
    func refreshSettings() { settingsView?.refresh() }
    func addApplication(_ url: URL) {
        guard Bundle(url: url)?.bundleIdentifier != nil else { message("应用无效", "请选择 .app 应用包。"); return }
        if !configuration.applications.contains(where: { $0.path == url.path }) {
            configuration.applications.append(AppReference(name: url.deletingPathExtension().lastPathComponent, path: url.path))
            persistSettings(); refreshSettings()
        }
    }
    private func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = "右键助手设置"; window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 840, height: 570)
        window.delegate = self; window.isReleasedWhenClosed = false; window.center()
        settingsView = SettingsView(app: self)
        window.contentView = settingsView
        statusLabel.textColor = .secondaryLabelColor
    }
    private func buildStatusMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "cursorarrow.click.2", accessibilityDescription: "右键助手")
        let menu = NSMenu()
        menu.addItem(withTitle: "设置…", action: #selector(showSettings), keyEquivalent: "")
        menu.addItem(.separator()); menu.addItem(withTitle: "退出右键助手", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }; statusItem.menu = menu
        let appMenu = NSMenu(); let root = NSMenuItem(); let submenu = NSMenu()
        submenu.addItem(withTitle: "右键助手设置…", action: #selector(showSettings), keyEquivalent: ",")
        submenu.addItem(.separator()); submenu.addItem(withTitle: "退出右键助手", action: #selector(quit), keyEquivalent: "q")
        for item in submenu.items { item.target = self }; root.submenu = submenu; appMenu.addItem(root)
        NSApp.mainMenu = appMenu
    }

    @objc func openInChatGPT(_ pasteboard: NSPasteboard, userData: String?, error errorPointer: AutoreleasingUnsafeMutablePointer<NSString?>) {
        receivedHandoff = true
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ??
            (pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] ?? []).map { URL(fileURLWithPath: $0) }
        do { let s = try Selection(urls: urls); runner.execute(.chatGPT, selection: s) }
        catch { errorPointer.pointee = error.localizedDescription as NSString }
    }
    @objc func translateText(_ pb: NSPasteboard, userData: String?, error errorPointer: AutoreleasingUnsafeMutablePointer<NSString?>) {
        receivedHandoff = true
        guard let text = pb.string(forType: .string) else { errorPointer.pointee = "没有选中的文字"; return }
        runner.translate(text, google: userData != "baidu")
    }
    @objc func generateQRCode(_ pb: NSPasteboard, userData: String?, error errorPointer: AutoreleasingUnsafeMutablePointer<NSString?>) {
        receivedHandoff = true
        guard let text = pb.string(forType: .string) else { errorPointer.pointee = "没有选中的文字"; return }
        do { try runner.showQR(text) } catch { errorPointer.pointee = error.localizedDescription as NSString }
    }
}

@main struct RightClickAssistantMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppController(); app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}
