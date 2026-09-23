// Draws the app icon into an .iconset directory: `icon <output.iconset>`. Run by build.sh, so the icon stays
// something you can read and change rather than a binary blob in the repository.
//
// The picture is the Figma one (file FGEXjUGH7Y5HcG7N8I6CTz, node 13:3): "vbh" in Helvetica Bold Oblique, black on
// white: «мир» typed in the wrong layout, the second half of the name. The key shape and its margin
// stay macOS's own, so the icon sits in line with the others in the Dock and in the Accessibility list.
import AppKit

func draw(side: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(side), pixelsHigh: Int(side),
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high

    // macOS leaves the artwork a margin of its own inside the canvas; the corner radius is Big Sur's squircle.
    let inset = side * 0.094, box = NSRect(x: inset, y: inset, width: side - 2 * inset, height: side - 2 * inset)
    let key = NSBezierPath(roundedRect: box, xRadius: box.width * 0.2237, yRadius: box.width * 0.2237)
    NSColor.white.setFill()
    key.fill()

    // Figma: 232 pt text on a 512 pt key, centred.
    let font = NSFont(name: "Helvetica-BoldOblique", size: box.width * 232 / 512)!
    let text = NSAttributedString(string: "vbh", attributes: [.font: font, .foregroundColor: NSColor.black])
    let size = text.size()
    text.draw(at: NSPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2))

    // Keeps the white key from bleeding into a white background.
    NSColor(white: 0, alpha: 0.12).setStroke()
    key.lineWidth = max(1, side * 0.004)
    key.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.removeItem(at: output)
try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for point in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        // Each size is drawn at its own resolution instead of shrinking one big image: thin strokes survive.
        let data = draw(side: CGFloat(point * scale)).representation(using: .png, properties: [:])!
        let name = "icon_\(point)x\(point)\(scale == 2 ? "@2x" : "").png"
        try! data.write(to: output.appendingPathComponent(name))
    }
}
print("wrote \(output.path)")
