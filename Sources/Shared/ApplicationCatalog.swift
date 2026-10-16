import Foundation

enum ApplicationCatalog {
    static var directories: [URL] {
        [URL(fileURLWithPath: "/Applications", isDirectory: true),
         FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
         URL(fileURLWithPath: "/System/Applications", isDirectory: true),
         URL(fileURLWithPath: "/System/Library/CoreServices/Applications", isDirectory: true)]
    }

    static func reference(at url: URL) -> AppReference? {
        guard url.isFileURL, url.path.hasPrefix("/"), !url.path.contains("\0"),
              url.pathExtension.lowercased() == "app",
              let values = try? url.resourceValues(forKeys: [.isDirectoryKey]), values.isDirectory == true,
              let bundle = Bundle(url: url), bundle.bundleIdentifier != nil,
              bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String == "APPL" else { return nil }
        let name = (bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (FileManager.default.displayName(atPath: url.path) as NSString).deletingPathExtension
        return AppReference(name: name, path: url.standardizedFileURL.resolvingSymlinksInPath().path)
    }

    // Traverse category folders (for example Utilities), but never an app's bundled helpers.
    static func scan(directories: [URL] = directories) -> [AppReference] {
        var apps: [AppReference] = []
        var paths = Set<String>()
        for directory in directories {
            guard let entries = FileManager.default.enumerator(at: directory,
                includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in entries where url.pathExtension.lowercased() == "app" {
                entries.skipDescendants()
                if let reference = reference(at: url), paths.insert(reference.path).inserted { apps.append(reference) }
            }
        }
        return apps.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.path < $1.path : order == .orderedAscending
        }
    }

    static func configuredApplication(path: String, configuration: AssistantConfiguration) throws -> URL {
        guard configuration.enabled(.otherApp), configuration.applications.contains(where: { $0.path == path && $0.enabled }) else {
            throw AssistantError.message("这个应用已停用或移除，请在“打开方式”设置中重新添加或启用。")
        }
        let url = URL(fileURLWithPath: path)
        guard reference(at: url) != nil else {
            throw AssistantError.message("未找到这个应用，可能已移动或卸载。请在“打开方式”设置中移除后重新添加。")
        }
        return url
    }
}
