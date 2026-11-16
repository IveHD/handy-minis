import AppKit

enum CaptureTool: Int {
    case select, arrow, rectangle, ellipse, pen, mosaic, redact, text, ocr, pointer, polyline

    var usesStyle: Bool {
        switch self {
        case .arrow, .rectangle, .ellipse, .pen, .text, .redact, .polyline: true
        default: false
        }
    }

    var usesLineStyle: Bool {
        switch self {
        case .arrow, .rectangle, .ellipse, .pen, .polyline: true
        default: false
        }
    }

}

enum CaptureLineStyle: Int {
    case solid, dashed

    static func dashPattern(for width: CGFloat) -> [CGFloat] {
        [max(7, width * 2.6), max(5, width * 2.2)]
    }

    func apply(to context: CGContext, width: CGFloat) {
        context.setLineDash(phase: 0, lengths: self == .dashed ? Self.dashPattern(for: width) : [])
    }
}

enum CaptureArrowShape: Int {
    case uniform, tapered
}

struct CaptureMark {
    let tool: CaptureTool
    var start: CGPoint
    var end: CGPoint
    var color: NSColor
    var width: CGFloat
    var points: [CGPoint] = []
    var text = ""

    var box: CGRect { selectionRect(from: start, to: end) }

    var textWidth: CGFloat = 0
    var lineStyle = CaptureLineStyle.solid
    var arrowShape = CaptureArrowShape.uniform

    private var textAttributes: [NSAttributedString.Key: Any] {
        [.foregroundColor: color, .font: Self.font(for: width)]
    }

    private var textLayoutWidth: CGFloat { textWidth > 0 ? textWidth : 10_000 }

    var visualBounds: CGRect {
        switch tool {
        case .text:
            let measured = (text as NSString).boundingRect(
                with: CGSize(width: textLayoutWidth, height: 10_000),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: textAttributes)
            return CGRect(origin: start, size: CGSize(width: ceil(measured.width), height: ceil(measured.height)))
        case .mosaic, .redact:
            return box
        case .arrow where arrowShape == .tapered:
            return taperedArrow(dashed: false).boundingBoxOfPath
        default:
            return outline.boundingBoxOfPath.insetBy(dx: -width / 2, dy: -width / 2)
        }
    }

    func contains(_ point: CGPoint) -> Bool {
        switch tool {
        case .text, .mosaic, .redact:
            return visualBounds.insetBy(dx: -4, dy: -4).contains(point)
        default:
            if tool == .arrow, arrowShape == .tapered {
                let shape = taperedArrow(dashed: false)
                if shape.contains(point) || shape.copy(strokingWithWidth: 8, lineCap: .round, lineJoin: .round,
                                                       miterLimit: 1).contains(point) { return true }
            }
            return outline.copy(strokingWithWidth: max(width + 8, 12), lineCap: .round,
                                lineJoin: .round, miterLimit: 1).contains(point)
        }
    }

    mutating func move(by delta: CGPoint) {
        func offset(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x + delta.x, y: point.y + delta.y)
        }
        start = offset(start)
        end = offset(end)
        points = points.map(offset)
    }

    private var outline: CGPath {
        let path = CGMutablePath()
        switch tool {
        case .rectangle:
            path.addRect(box)
        case .ellipse:
            path.addEllipse(in: box)
        case .pen, .polyline:
            path.addLines(between: [start] + points + [end])
        case .arrow:
            path.move(to: start)
            path.addLine(to: end)
            path.addPath(openArrowhead)
        default:
            break
        }
        return path
    }

    private var openArrowhead: CGPath {
        let length = hypot(end.x - start.x, end.y - start.y)
        let angle = atan2(end.y - start.y, end.x - start.x)
        let head = min(10 + 2 * width, length * 0.6)
        let path = CGMutablePath()
        for offset in [-CGFloat.pi / 6, .pi / 6] {
            path.move(to: end)
            path.addLine(to: CGPoint(x: end.x - head * cos(angle + offset),
                                     y: end.y - head * sin(angle + offset)))
        }
        return path
    }

    private func taperedArrow(dashed: Bool) -> CGPath {
        let path = CGMutablePath()
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 0 else { return path }
        let shaftLength = length - min(10 + 2 * width, length * 0.5)
        let shaftHalfWidth = min(width * 0.9, length * 0.125)
        let tailHalfWidth = shaftHalfWidth * 0.18
        let headHalfWidth = min(max(width * 1.8, 6), length * 0.33)
        func point(at distance: CGFloat, offset: CGFloat) -> CGPoint {
            CGPoint(x: start.x + (distance * dx - offset * dy) / length,
                    y: start.y + (distance * dy + offset * dx) / length)
        }
        func addShaft(from first: CGFloat, to last: CGFloat) {
            let firstWidth = tailHalfWidth + (shaftHalfWidth - tailHalfWidth) * first / shaftLength
            let lastWidth = tailHalfWidth + (shaftHalfWidth - tailHalfWidth) * last / shaftLength
            path.addLines(between: [point(at: first, offset: -firstWidth), point(at: last, offset: -lastWidth),
                                    point(at: last, offset: lastWidth), point(at: first, offset: firstWidth)])
            path.closeSubpath()
        }
        if dashed {
            let pattern = CaptureLineStyle.dashPattern(for: width)
            var distance: CGFloat = 0
            while distance < shaftLength {
                addShaft(from: distance, to: min(distance + pattern[0], shaftLength))
                distance += pattern[0] + pattern[1]
            }
        } else {
            addShaft(from: 0, to: shaftLength)
        }
        path.addLines(between: [point(at: shaftLength, offset: -headHalfWidth), end,
                                point(at: shaftLength, offset: headHalfWidth)])
        path.closeSubpath()
        return path
    }

    func drawBody(in context: CGContext) {
        if tool == .text {
            (text as NSString).draw(with: CGRect(x: start.x, y: start.y, width: textLayoutWidth, height: 10_000),
                                    options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: textAttributes)
            return
        }
        if tool == .arrow, arrowShape == .tapered {
            context.setFillColor(color.cgColor)
            context.addPath(taperedArrow(dashed: lineStyle == .dashed))
            context.fillPath()
            return
        }

        context.setLineWidth(width)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(color.cgColor)
        lineStyle.apply(to: context, width: width)
        if tool == .arrow, lineStyle == .dashed {
            context.move(to: start)
            context.addLine(to: end)
            context.strokePath()
            CaptureLineStyle.solid.apply(to: context, width: width)
            context.addPath(openArrowhead)
        } else {
            context.addPath(outline)
        }
        context.strokePath()
    }

    static func font(for width: CGFloat) -> NSFont {
        .systemFont(ofSize: 12 + 2 * width, weight: .semibold)
    }
}

func selectionRect(from first: CGPoint, to second: CGPoint) -> CGRect {
    CGRect(x: min(first.x, second.x), y: min(first.y, second.y),
           width: abs(first.x - second.x), height: abs(first.y - second.y))
}
