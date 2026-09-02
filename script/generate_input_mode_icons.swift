import AppKit

struct IconSpec {
    let size: CGFloat
    let outputPath: String
}

let specs = [
    IconSpec(size: 16, outputPath: "Source/Images/Bopomofo.tiff"),
    IconSpec(size: 32, outputPath: "Source/Images/Bopomofo@2x.tiff"),
    IconSpec(size: 16, outputPath: "Source/Images/PlainBopomofo.tiff"),
    IconSpec(size: 32, outputPath: "Source/Images/PlainBopomofo@2x.tiff"),
]

let fileManager = FileManager.default
let baseURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)

for spec in specs {
    let rect = NSRect(x: 0, y: 0, width: spec.size, height: spec.size)
    let image = NSImage(size: rect.size)

    image.lockFocus()
    NSColor.clear.setFill()
    rect.fill()

    let inset = spec.size * 0.06
    let badgeRect = rect.insetBy(dx: inset, dy: inset)
    let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: spec.size * 0.22, yRadius: spec.size * 0.22)
    NSColor(calibratedRed: 0.11, green: 0.45, blue: 0.95, alpha: 1.0).setFill()
    badgePath.fill()

    let fontSize = spec.size * 0.52
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.alignment = .center

    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .black),
        .foregroundColor: NSColor.white,
        .paragraphStyle: paragraphStyle,
    ]

    let text = NSString(string: "YA")
    let textRect = text.boundingRect(with: badgeRect.size, options: .usesLineFragmentOrigin, attributes: attributes)
    let drawRect = NSRect(
        x: badgeRect.minX,
        y: badgeRect.minY + (badgeRect.height - textRect.height) / 2 - spec.size * 0.02,
        width: badgeRect.width,
        height: textRect.height)
    text.draw(in: drawRect, withAttributes: attributes)
    image.unlockFocus()

    guard
        let tiffData = image.tiffRepresentation
    else {
        fputs("Failed to render \(spec.outputPath)\n", stderr)
        exit(1)
    }

    let outputURL = baseURL.appendingPathComponent(spec.outputPath)
    try tiffData.write(to: outputURL)
    print("Wrote \(outputURL.path)")
}
