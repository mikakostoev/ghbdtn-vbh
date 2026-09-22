// Draws the app icon into an .iconset directory: `icon <output.iconset>`. Run by build.sh, so the icon stays
// something you can read and change rather than a binary blob in the repository.
//
// The picture is the app itself: one key, split down the diagonal into the Latin half and the Cyrillic one.
// At 16 px in the Accessibility list the letters are gone and only the split is left, which is the point —
// a program asking to watch every keystroke should at least be recognisable there.
import AppKit

let light = NSColor(srgbRed: 0.961, green: 0.961, blue: 0.969, alpha: 1)
let accent = NSColor(srgbRed: 0.157, green: 0.412, blue: 0.898, alpha: 1)
let ink = NSColor(srgbRed: 0.106, green: 0.114, blue: 0.129, alpha: 1)

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
    light.setFill()
    key.fill()

    NSGraphicsContext.saveGraphicsState()
    key.addClip()
    let half = NSBezierPath()
    half.move(to: NSPoint(x: box.minX, y: box.minY))
    half.line(to: NSPoint(x: box.maxX, y: box.minY))
    half.line(to: NSPoint(x: box.maxX, y: box.maxY))
    half.close()
    accent.setFill()
    half.fill()
    NSGraphicsContext.restoreGraphicsState()

    func letter(_ text: String, color: NSColor, at point: NSPoint) {
        let font = NSFont.systemFont(ofSize: box.width * 0.42, weight: .bold)
        let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        let size = string.size()
        string.draw(at: NSPoint(x: point.x - size.width / 2, y: point.y - size.height / 2))
    }
    letter("A", color: ink, at: NSPoint(x: box.minX + box.width * 0.31, y: box.minY + box.height * 0.68))
    letter("Я", color: .white, at: NSPoint(x: box.minX + box.width * 0.69, y: box.minY + box.height * 0.32))

    // Keeps the light half from bleeding into a white background.
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
