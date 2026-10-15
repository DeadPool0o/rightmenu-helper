import AppKit

// Render the existing settings logo as transparent, native macOS icon artwork.
// Usage: xcrun swift Tools/GenerateAppIcon.swift build/AppIcon.iconset
// Then: iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
NSApplication.shared.appearance = NSAppearance(named: .aqua)

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let size = CGFloat(pixels)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                             isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap),
              let symbol = NSImage(systemSymbolName: "cursorarrow.click.2", accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size * 0.61, weight: .medium)
                    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))) else {
            fatalError("Unable to render the application icon at \(pixels) pixels.")
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.systemBlue.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size, height: size),
                     xRadius: size * 0.23, yRadius: size * 0.23).fill()
        symbol.draw(in: NSRect(x: size * 0.18, y: size * 0.18, width: size * 0.64, height: size * 0.64))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            fatalError("Unable to encode the application icon at \(pixels) pixels.")
        }
        let name = "icon_\(points)x\(points)" + (scale == 2 ? "@2x" : "") + ".png"
        try png.write(to: output.appendingPathComponent(name), options: .atomic)
    }
}
