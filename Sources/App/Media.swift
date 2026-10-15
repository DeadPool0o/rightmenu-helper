import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers

enum MediaWork {
    static func image(_ source: URL) throws -> CGImage {
        guard let decoder = CGImageSourceCreateWithURL(source as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(decoder, 0, nil) else {
            throw AssistantError.message("无法读取图片：\(source.lastPathComponent)")
        }
        return image
    }

    static func encode(_ image: CGImage, type: String, to url: URL) throws {
        let supported = CGImageDestinationCopyTypeIdentifiers() as! [String]
        let bytes = NSMutableData()
        guard supported.contains(type), let destination = CGImageDestinationCreateWithData(bytes, type as CFString, 1, nil) else {
            throw AssistantError.message("当前 macOS 不支持这种图片编码，请使用其他格式。")
        }
        CGImageDestinationAddImage(destination, image,
                                  [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw AssistantError.message("图片保存失败。") }
        try (bytes as Data).write(to: url, options: .withoutOverwriting)
    }

    static func convert(_ source: URL, action: MenuAction) throws -> URL {
        let formats: [MenuAction: (String, String)] = [.png: ("public.png", "png"), .jpeg: ("public.jpeg", "jpg"),
                                                    .heic: ("public.heic", "heic"), .webp: ("org.webmproject.webp", "webp")]
        guard let (type, ext) = formats[action] else { throw AssistantError.message("未知图片格式。") }
        let out = FilePolicy.uniqueURL(in: source.deletingLastPathComponent(),
                                      name: source.deletingPathExtension().lastPathComponent + "." + ext)
        try encode(image(source), type: type, to: out)
        return out
    }

    static func square(_ image: CGImage, size: Int) throws -> CGImage {
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size*4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw AssistantError.message("无法创建图片画布。")
        }
        let scale = min(CGFloat(size)/CGFloat(image.width), CGFloat(size)/CGFloat(image.height))
        let w = CGFloat(image.width)*scale, h = CGFloat(image.height)*scale
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: (CGFloat(size)-w)/2, y: (CGFloat(size)-h)/2, width: w, height: h))
        guard let out = ctx.makeImage() else { throw AssistantError.message("无法生成图片。") }
        return out
    }

    static func iconSet(_ source: URL, ios: Bool) throws -> URL {
        let cg = try image(source)
        let folder = FilePolicy.uniqueURL(in: source.deletingLastPathComponent(),
                                         name: source.deletingPathExtension().lastPathComponent + (ios ? ".appiconset" : ".iconset"))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        do {
            if ios {
                let specs: [(String, Double, Int)] = [
                    ("iphone",20,2),("iphone",20,3),("iphone",29,2),("iphone",29,3),
                    ("iphone",40,2),("iphone",40,3),("iphone",60,2),("iphone",60,3),
                    ("ipad",20,1),("ipad",20,2),("ipad",29,1),("ipad",29,2),
                    ("ipad",40,1),("ipad",40,2),("ipad",76,1),("ipad",76,2),("ipad",83.5,2),
                    ("ios-marketing",1024,1)]
                var entries: [[String: String]] = []
                for (idiom, points, scale) in specs {
                    let label = points == points.rounded() ? String(Int(points)) : String(points)
                    let name = "icon_\(idiom)_\(label)@\(scale)x.png"
                    try encode(square(cg, size: Int(points*Double(scale))), type: "public.png", to: folder.appendingPathComponent(name))
                    entries.append(["idiom": idiom, "size": "\(label)x\(label)", "scale": "\(scale)x", "filename": name])
                }
                let contents: [String: Any] = ["images": entries, "info": ["author": "rightclick-assistant", "version": 1]]
                try JSONSerialization.data(withJSONObject: contents, options: .prettyPrinted)
                    .write(to: folder.appendingPathComponent("Contents.json"))
            } else {
                for points in [16,32,128,256,512] {
                    for scale in [1,2] {
                        let name = "icon_\(points)x\(points)" + (scale == 2 ? "@2x" : "") + ".png"
                        try encode(square(cg, size: points*scale), type: "public.png", to: folder.appendingPathComponent(name))
                    }
                }
            }
            return folder
        } catch { try? FileManager.default.removeItem(at: folder); throw error }
    }

    static func qr(_ text: String) throws -> NSImage {
        guard !text.isEmpty, let filter = CIFilter(name: "CIQRCodeGenerator") else {
            throw AssistantError.message("请输入需要生成二维码的文字。")
        }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = CIContext(options: [.useSoftwareRenderer: true]).createCGImage(output, from: output.extent) else {
            throw AssistantError.message("内容过长或无法生成二维码。")
        }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}

enum CommandWork {
    @discardableResult static func run(_ path: String, _ arguments: [String], directory: URL? = nil) throws -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = arguments
        p.currentDirectoryURL = directory
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        let output = String(decoding: data.prefix(65536), as: UTF8.self)
        guard p.terminationStatus == 0 else {
            throw AssistantError.message("\(URL(fileURLWithPath: path).lastPathComponent) 操作失败（\(p.terminationStatus)，\(p.terminationReason == .exit ? "退出" : "信号")）：\n" + output)
        }
        return output
    }
    static var sevenZip: String? {
        ["/opt/homebrew/bin/7zz", "/usr/local/bin/7zz", "/opt/homebrew/bin/7z", "/usr/local/bin/7z"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    static func compress(_ urls: [URL], to destination: URL, seven: Bool) throws {
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("rightclick-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: staging) }
        let items = staging.appendingPathComponent("items")
        try FileManager.default.createDirectory(at: items, withIntermediateDirectories: false)
        for source in urls {
            let target = FilePolicy.uniqueURL(in: items, name: source.lastPathComponent)
            try FileManager.default.copyItem(at: source, to: target)
        }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw AssistantError.message("目标文件已存在，请选择其他名称。")
        }
        let temporaryArchive = staging.appendingPathComponent(seven ? "output.7z" : "output.zip")
        do {
            if seven {
                guard let engine = sevenZip else { throw AssistantError.message("请安装 Keka 或 7zz 后再使用 7z。") }
                try run(engine, ["a", "-t7z", temporaryArchive.path, "./", "-snl", "-y"], directory: items)
            } else {
                try run("/usr/bin/zip", ["-q", "-r", "-y", temporaryArchive.path, "./"], directory: items)
            }
            try FileManager.default.moveItem(at: temporaryArchive, to: destination)
        } catch { throw error }
    }
    static func extractZIP(_ source: URL) throws -> URL {
        let data = try Data(contentsOf: source, options: .mappedIfSafe)
        let size = try ZIPPolicy.validate(data)
        guard size <= 2_147_483_648 else { throw AssistantError.message("预计解压超过 2 GB，请使用 Keka 解压。") }
        let target = FilePolicy.uniqueURL(in: source.deletingLastPathComponent(), name: source.deletingPathExtension().lastPathComponent)
        let snapshot = FileManager.default.temporaryDirectory.appendingPathComponent("rightclick-archive-" + UUID().uuidString + ".zip")
        try data.write(to: snapshot, options: .withoutOverwriting)
        defer { try? FileManager.default.removeItem(at: snapshot) }
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        do { try run("/usr/bin/unzip", ["-q", snapshot.path, "-d", target.path]); return target }
        catch { try? FileManager.default.removeItem(at: target); throw error }
    }
}
