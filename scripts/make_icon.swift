// Рисует иконку приложения и сохраняет набор PNG для iconutil.
// Использование: swift scripts/make_icon.swift build/AppIcon.iconset
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func render(_ px: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)

    // Фон: скруглённый квадрат с градиентом.
    let inset = s * 0.09
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = rect.width * 0.23
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    let gradient = NSGradient(
        starting: NSColor(calibratedRed: 0.16, green: 0.56, blue: 1.00, alpha: 1),
        ending: NSColor(calibratedRed: 0.38, green: 0.24, blue: 0.86, alpha: 1))
    gradient?.draw(in: path, angle: -90)

    // Пузырь-подложка.
    let bubble = NSBezierPath(
        roundedRect: NSRect(x: s * 0.50, y: s * 0.16, width: s * 0.32, height: s * 0.28),
        xRadius: s * 0.07, yRadius: s * 0.07)
    NSColor.white.withAlphaComponent(0.92).setFill()
    bubble.fill()

    // Буква V.
    let vFont = NSFont.systemFont(ofSize: s * 0.56, weight: .black)
    let v = NSAttributedString(string: "V", attributes: [.font: vFont, .foregroundColor: NSColor.white])
    let vSize = v.size()
    v.draw(at: NSPoint(x: s * 0.40 - vSize.width / 2, y: s * 0.53 - vSize.height / 2))

    // Иероглиф «文» в пузыре.
    let zFont = NSFont.systemFont(ofSize: s * 0.20, weight: .bold)
    let z = NSAttributedString(string: "文", attributes: [
        .font: zFont,
        .foregroundColor: NSColor(calibratedRed: 0.30, green: 0.32, blue: 0.90, alpha: 1),
    ])
    let zSize = z.size()
    z.draw(at: NSPoint(x: s * 0.66 - zSize.width / 2, y: s * 0.30 - zSize.height / 2))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in sizes {
    guard let data = render(px) else { fatalError("render failed for \(px)") }
    try data.write(to: URL(fileURLWithPath: outDir).appendingPathComponent("\(name).png"))
}
print("Icon set written to \(outDir)")
