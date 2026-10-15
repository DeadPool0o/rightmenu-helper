import AppKit
import UniformTypeIdentifiers

/// Ask Icon Services for the current macOS artwork, including its folder material and emblem.
/// Settings, Finder menus and the file operation must all use this same source.
enum NativeFileIcons {
    private static var cached: [String: NSImage] = [:]

    static func image(for preset: IconPreset, size: CGFloat? = nil) -> NSImage? {
        if cached[preset.symbol] == nil {
            // CoreTypes declares special folder icon identifiers, but UTType.init does not
            // expose these as ordinary content types. Import the system declarations explicitly.
            let type = preset.typeIdentifier == "public.folder" ? UTType.folder :
                UTType(importedAs: preset.typeIdentifier, conformingTo: .folder)
            // NSWorkspace returns a live Icon Services proxy. Freeze the complete artwork
            // before setIcon(nil) invalidates its backing cache during replacement.
            cached[preset.symbol] = rasterized(NSWorkspace.shared.icon(for: type))
        }
        guard let image = cached[preset.symbol]?.copy() as? NSImage else { return nil }
        // Icon Services images draw at the requested resolution; the operation needs full size.
        let side = size ?? 1024
        image.size = NSSize(width: side, height: side)
        image.isTemplate = false
        image.accessibilityDescription = preset.name
        return image
    }

    private static func rasterized(_ source: NSImage) -> NSImage? {
        let icon = NSImage(size: NSSize(width: 1024, height: 1024))
        for pixels in [16, 32, 64, 128, 256, 512, 1024] {
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels,
                pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                let context = NSGraphicsContext(bitmapImageRep: bitmap),
                let frame = source.copy() as? NSImage else { return nil }
            frame.size = NSSize(width: pixels, height: pixels)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            frame.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero,
                operation: .copy, fraction: 1, respectFlipped: false, hints: nil)
            NSGraphicsContext.restoreGraphicsState()
            icon.addRepresentation(bitmap)
        }
        icon.isTemplate = false
        return icon
    }
}
