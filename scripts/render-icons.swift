// Run from the repository root: scripts/render-icons.sh
import AppKit

let files = FileManager.default
let iconset = URL(fileURLWithPath: ".build/DeskKit.iconset")
try files.createDirectory(at: iconset, withIntermediateDirectories: true)

func drawMark(in context: CGContext) {
    context.beginPath()
    context.move(to: CGPoint(x: 2, y: 3))
    context.addLine(to: CGPoint(x: 2, y: 13))
    context.addLine(to: CGPoint(x: 5, y: 13))
    context.addCurve(to: CGPoint(x: 5, y: 3), control1: CGPoint(x: 11, y: 13), control2: CGPoint(x: 11, y: 3))
    context.closePath()
    context.move(to: CGPoint(x: 12, y: 3))
    context.addLine(to: CGPoint(x: 12, y: 13))
    context.move(to: CGPoint(x: 18, y: 13))
    context.addLine(to: CGPoint(x: 12, y: 7))
    context.move(to: CGPoint(x: 14, y: 9))
    context.addLine(to: CGPoint(x: 18, y: 3))
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.setLineWidth(1.7)
    context.strokePath()
}

func render(width: Int, height: Int, to url: URL, draw: (CGContext) -> Void) throws {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: 0, space: colorSpace,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    draw(context)
    let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
    try bitmap.representation(using: .png, properties: [:])!.write(to: url)
}

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let suffix = scale == 1 ? "" : "@2x"
        let url = iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        try render(width: pixels, height: pixels, to: url) { context in
            let unit = CGFloat(pixels) / 1024
            context.scaleBy(x: unit, y: unit)
            let tile = CGPath(roundedRect: CGRect(x: 84, y: 84, width: 856, height: 856),
                              cornerWidth: 194, cornerHeight: 194, transform: nil)
            context.saveGState()
            context.addPath(tile)
            context.clip()
            let colors = [CGColor(red: 0.06, green: 0.15, blue: 0.30, alpha: 1),
                          CGColor(red: 0.13, green: 0.37, blue: 0.68, alpha: 1)]
            let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                      colors: colors as CFArray, locations: [0, 1])!
            context.drawLinearGradient(gradient, start: CGPoint(x: 850, y: 84),
                                       end: CGPoint(x: 170, y: 940), options: [])
            context.restoreGState()
            context.translateBy(x: 192, y: 256)
            context.scaleBy(x: 32, y: 32)
            context.setStrokeColor(red: 0.92, green: 0.98, blue: 1, alpha: 1)
            drawMark(in: context)
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
    let url = URL(fileURLWithPath: "Resources/StatusIconTemplate\(suffix).png")
    try render(width: 20 * scale, height: 16 * scale, to: url) { context in
        context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        context.setStrokeColor(gray: 0, alpha: 1)
        drawMark(in: context)
    }
}
