import AppKit
import Darwin

enum FileIconWork {
    static func apply(_ image: NSImage?, to url: URL) throws {
        let workspace = NSWorkspace.shared
        ActionLog.record("icon write input reps=" + String(image?.representations.count ?? 0) + " custom=" + String(hasCustomIcon(url)))
        var previous: NSImage?
        if image != nil && hasCustomIcon(url) {
            let old = workspace.icon(forFile: url.path)
            old.size = NSSize(width: 1024, height: 1024)
            previous = old.tiffRepresentation.flatMap { NSImage(data: $0) }
        }
        if image != nil && previous != nil {
            // Apple's DTS workaround: replacing an existing custom icon can retain Finder's
            // old cache. Clearing first forces the default-icon discovery path before writing.
            // https://developer.apple.com/forums/thread/788252
            guard workspace.setIcon(nil, forFile: url.path, options: []) else {
                throw AssistantError.message("无法清除旧图标：" + url.lastPathComponent)
            }
            // Finder must finish rediscovering the default icon before the replacement
            // is written; otherwise its pending clear can remove the new icon as well.
            refreshFinderItem(url)
            ActionLog.record("icon after clear refresh custom=" + String(hasCustomIcon(url)))
        }
        guard workspace.setIcon(image, forFile: url.path, options: []) else {
            // Restore the prior custom icon if the new write fails after clearing it.
            if image != nil { _ = workspace.setIcon(previous, forFile: url.path, options: []) }
            throw AssistantError.message((image == nil ? "图标恢复失败：" : "图标设置失败：") + url.lastPathComponent)
        }
        ActionLog.record("icon write persisted=" + String(hasCustomIcon(url)))
        workspace.noteFileSystemChanged(url.deletingLastPathComponent().path)
        // A replacement is written after Finder has rediscovered the default icon.
        // Refreshing again here can discard the just-written resource on current macOS.
        if image == nil { refreshFinderItem(url) }
        ActionLog.record("icon after refresh persisted=" + String(hasCustomIcon(url)))
        guard hasCustomIcon(url) == (image != nil) else {
            throw AssistantError.message("图标未能保存：" + url.lastPathComponent)
        }
    }

    private static func refreshFinderItem(_ url: URL) {
        // Finder.sdef defines update as fndr/fupd: refresh this item's on-disk metadata.
        // Unlike a directory notification, this asks Finder to invalidate the item's icon.
        let event = NSAppleEventDescriptor(eventClass: 0x666e6472, eventID: 0x66757064,
            targetDescriptor: NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder"),
            returnID: -1, transactionID: 0)
        event.setDescriptor(NSAppleEventDescriptor(fileURL: url), forKeyword: 0x2d2d2d2d)
        event.setDescriptor(NSAppleEventDescriptor(boolean: false), forKeyword: 0x7265673f)
        // kAEDoNotPromptForUserConsent keeps this metadata refresh from requesting access.
        let noConsentPrompt = NSAppleEventDescriptor.SendOptions(rawValue: 0x00020000)
        do {
            let reply = try event.sendEvent(options: [.waitForReply, .neverInteract, noConsentPrompt], timeout: 2)
            let errorNumber = reply.paramDescriptor(forKeyword: 0x6572726e)?.int32Value ?? 0
            ActionLog.record("Finder icon refresh result=" + String(errorNumber))
        } catch {
            ActionLog.record("Finder icon refresh failed=" + error.localizedDescription)
        }
    }

    private static func hasCustomIcon(_ url: URL) -> Bool {
        var info = [UInt8](repeating: 0, count: 32)
        let length = url.path.withCString { path in
            info.withUnsafeMutableBytes { bytes in
                getxattr(path, "com.apple.FinderInfo", bytes.baseAddress, bytes.count, 0, 0)
            }
        }
        // Finder's kHasCustomIcon is 0x0400 in the big-endian Finder flags at bytes 8–9.
        return length == 32 && info[8] & 4 != 0
    }
}
