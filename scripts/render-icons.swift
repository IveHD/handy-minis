// Run from the repository root: scripts/render-icons.sh
// One geometric HM ligature drives the app icon, menu bar, SVGs and social card.
import AppKit

let files = FileManager.default
let iconset = URL(fileURLWithPath: ".build/HandyMinis.iconset")
let assets = URL(fileURLWithPath: "docs/assets")
try files.createDirectory(at: iconset, withIntermediateDirectories: true)
try files.createDirectory(at: assets, withIntermediateDirectories: true)

let forest = NSColor(srgbRed: 0.075, green: 0.22, blue: 0.18, alpha: 1)
let paper = NSColor(srgbRed: 0.98, green: 0.97, blue: 0.92, alpha: 1)
let lime = NSColor(srgbRed: 0.78, green: 0.92, blue: 0.40, alpha: 1)
// H and M share the x=460 stem. The H crossbar meets the M's folded diagonal.
let hPoints: [[CGPoint]] = [[CGPoint(x: 246, y: 302), CGPoint(x: 246, y: 722)],
                           [CGPoint(x: 246, y: 512), CGPoint(x: 460, y: 512)]]
let mPoints = [[CGPoint(x: 460, y: 722), CGPoint(x: 460, y: 302),
                CGPoint(x: 619, y: 512), CGPoint(x: 778, y: 302), CGPoint(x: 778, y: 722)]]

func stroke(_ paths: [[CGPoint]], in context: CGContext, color: NSColor, width: CGFloat) {
    context.setStrokeColor(color.cgColor)
    context.setLineWidth(width)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    for points in paths {
        context.beginPath()
        context.move(to: points[0])
        for point in points.dropFirst() { context.addLine(to: point) }
        context.strokePath()
    }
}

func drawMark(in context: CGContext, monochrome: Bool = false, lineWidth: CGFloat = 88) {
    stroke(hPoints, in: context, color: monochrome ? .black : paper, width: lineWidth)
    stroke(mPoints, in: context, color: monochrome ? .black : lime, width: lineWidth)
}

func drawIcon(in context: CGContext) {
    let tile = CGPath(roundedRect: CGRect(x: 64, y: 64, width: 896, height: 896),
                      cornerWidth: 206, cornerHeight: 206, transform: nil)
    context.setFillColor(forest.cgColor)
    context.addPath(tile)
    context.fillPath()
    // A quiet inset edge gives the flat mark a tactile macOS tile without visual noise.
    context.setStrokeColor(NSColor.white.withAlphaComponent(0.13).cgColor)
    context.setLineWidth(3)
    context.addPath(CGPath(roundedRect: CGRect(x: 79, y: 79, width: 866, height: 866),
                          cornerWidth: 192, cornerHeight: 192, transform: nil))
    context.strokePath()
    drawMark(in: context)
}

func render(width: Int, height: Int, to url: URL, draw: (CGContext) -> Void) throws {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Use a top-left coordinate system in both raster and SVG assets.
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)
    draw(context)
    let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
    try bitmap.representation(using: .png, properties: [:])!.write(to: url)
}

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let suffix = scale == 1 ? "" : "@2x"
        try render(width: pixels, height: pixels,
                   to: iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")) { context in
            context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
            drawIcon(in: context)
        }
    }
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { exit(iconutil.terminationStatus) }

for scale in [1, 2] {
    let suffix = scale == 1 ? "" : "@2x"
    try render(width: 18 * scale, height: 18 * scale,
               to: URL(fileURLWithPath: "Resources/StatusIconTemplate\(suffix).png")) { context in
        context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        // Optical size ~14×13 pt, with a 1.3 pt stroke and generous side bearings.
        context.translateBy(x: 2.5, y: 3.25)
        context.scaleBy(x: 13 / 532, y: 11.5 / 420)
        context.translateBy(x: -246, y: -302)
        drawMark(in: context, monochrome: true, lineWidth: 50)
    }
}

func svgPaths(colorH: String, colorM: String) -> String {
    func path(_ points: [CGPoint]) -> String {
        points.enumerated().map { "\($0.offset == 0 ? "M" : "L")\(Int($0.element.x)) \(Int($0.element.y))" }.joined(separator: " ")
    }
    return (hPoints.map { "<path d=\"\(path($0))\" stroke=\"\(colorH)\"/>" }
        + mPoints.map { "<path d=\"\(path($0))\" stroke=\"\(colorM)\"/>" }).joined(separator: "\n")
}
let iconSVG = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" role="img" aria-labelledby="title">
<title id="title">HandyMinis HM monogram</title>
<rect x="64" y="64" width="896" height="896" rx="206" fill="#13382e"/>
<rect x="79" y="79" width="866" height="866" rx="192" fill="none" stroke="#fff" stroke-opacity=".13" stroke-width="3"/>
<g fill="none" stroke-width="88" stroke-linecap="round" stroke-linejoin="round">
\(svgPaths(colorH: "#faf7eb", colorM: "#c7eb66"))
</g></svg>
"""
try iconSVG.write(to: assets.appendingPathComponent("handy-minis.svg"), atomically: true, encoding: .utf8)
let markSVG = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="202 258 620 508" role="img" aria-labelledby="title">
<title id="title">HandyMinis HM monogram</title>
<g fill="none" stroke-width="88" stroke-linecap="round" stroke-linejoin="round">
\(svgPaths(colorH: "currentColor", colorM: "currentColor"))
</g></svg>
"""
try markSVG.write(to: assets.appendingPathComponent("hm-mark.svg"), atomically: true, encoding: .utf8)
for (name, size) in [("app-icon", 512), ("apple-touch-icon", 180), ("favicon-32", 32)] {
    try render(width: size, height: size, to: assets.appendingPathComponent("\(name).png")) { context in
        context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
        drawIcon(in: context)
    }
}

func text(_ value: String, x: CGFloat, y: CGFloat, size: CGFloat, color: NSColor, weight: NSFont.Weight = .regular) {
    (value as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
}
try render(width: 1200, height: 630, to: assets.appendingPathComponent("social-card.png")) { context in
    context.setFillColor(paper.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: 1200, height: 630))
    context.saveGState()
    context.translateBy(x: 56, y: 110)
    context.scaleBy(x: 0.38, y: 0.38)
    drawIcon(in: context)
    context.restoreGState()
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
    text("HandyMinis", x: 480, y: 178, size: 76, color: forest, weight: .bold)
    text("顺手小工具", x: 484, y: 280, size: 36, color: forest, weight: .medium)
    text("剪贴板  /  截图 OCR  /  窗口整理", x: 484, y: 354, size: 25, color: forest)
    text("小工具，每天都用得上。", x: 82, y: 550, size: 22, color: forest)
    text("FOR macOS", x: 1000, y: 550, size: 18, color: forest, weight: .semibold)
    NSGraphicsContext.restoreGraphicsState()
}
print("Generated HandyMinis app, menu-bar and website brand assets.")
