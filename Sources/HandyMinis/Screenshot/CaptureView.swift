import AppKit
import QuartzCore
import ImageIO
import UniformTypeIdentifiers

private final class DragButton: NSButton {
    var startDrag: ((NSEvent) -> Void)?

    override func mouseDown(with event: NSEvent) {
        while let next = window?.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) {
            if next.type == .leftMouseUp { return }
            let distance = hypot(next.locationInWindow.x - event.locationInWindow.x,
                                 next.locationInWindow.y - event.locationInWindow.y)
            if distance >= 4 {
                startDrag?(next)
                return
            }
        }
    }
}

final class CaptureView: NSView, NSDraggingSource, NSTextViewDelegate {
    var onClose: ((Bool) -> Void)?
    var onSave: ((Data) -> Void)?
    var onDragVisibility: ((Bool) -> Void)?
    var beginExport: (() -> Bool)?
    var endExport: (() -> Void)?

    private let windowSuggestions: [CGRect]
    private var suggestedWindow: CGRect?
    private var clickedWindow: CGRect?
    private var tracking: NSTrackingArea?

    private let screenshot: CGImage
    private var selection = CGRect.zero
    private var tool = CaptureTool.select
    private var marks: [CaptureMark] = []
    private var undoMarks: [[CaptureMark]] = []
    private var redoMarks: [[CaptureMark]] = []
    private var selectedMark: Int?
    private var movingMark: (index: Int, origin: CGPoint, before: [CaptureMark])?
    private var draft: CaptureMark?
    private var linePoints: [CGPoint] = []
    private var lineHover: CGPoint?
    private let lineHelp = NSTextField(labelWithString: "逐点单击 · 双击或回车完成")
    private var maskColor = NSColor.black
    private var annotationColor = NSColor(srgbRed: 1, green: 0.24, blue: 0.20, alpha: 1)
    private var annotationWidth: CGFloat = 3
    private var textWidth: CGFloat = 3
    private var lineStyle = CaptureLineStyle.solid
    private var arrowShape = CaptureArrowShape.tapered
    private var textEditor: CaptureTextEditor?
    private var textBox: NSScrollView?
    private var editingMark: Int?
    private var editingText: CaptureMark?

    private var textLines: [CaptureTextLine]?
    private var textAnchor: CaptureTextPosition?
    private var textEnd: CaptureTextPosition?
    private var recognitionID: UUID?
    private var anchor: CGPoint?
    private var resizing = false
    private var dragFolder: URL?
    private var isEncodingPNG = false
    private let toolbar = NSVisualEffectView()
    private var toolButtons: [CaptureTool: NSButton] = [:]
    private lazy var copyButton = NSButton(title: "复制图片", target: self, action: #selector(copyImage))
    private lazy var saveButton = iconButton("square.and.arrow.down", "保存 PNG", #selector(save))
    private let toolbarContent = NSStackView()
    private let styles = NSStackView()
    private let ocrControls = NSStackView()
    private let ocrStatus = NSTextField(labelWithString: "")
    private lazy var copyTextButton = makeCopyTextButton()
    private var colorButtons: [NSButton] = []

    private lazy var mosaic: CGImage? = {
        let width = max(1, Int((bounds.width / 12).rounded(.up)))
        let height = max(1, Int((bounds.height / 12).rounded(.up)))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(screenshot, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }()

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(frame: CGRect, image: CGImage, windowSuggestions: [CGRect] = []) {
        self.windowSuggestions = windowSuggestions
        screenshot = image
        super.init(frame: frame)
        configureToolbar()
    }

    required init?(coder: NSCoder) { nil }

    private func configureToolbar() {
        toolbar.material = .popover
        toolbar.blendingMode = .withinWindow
        toolbar.state = .active
        toolbar.wantsLayer = true
        toolbar.layer?.cornerRadius = 14
        toolbar.layer?.cornerCurve = .continuous
        toolbar.layer?.masksToBounds = true

        let controls = NSStackView()
        controls.spacing = 4
        let tools: [(CaptureTool, String, String)] = [
            (.select, "arrow.up.left.and.arrow.down.right", "调整选区 (V)"),
            (.pointer, "cursorarrow", "选择并移动标记 (S)"),
            (.rectangle, "rectangle", "矩形 (R)"),
            (.ellipse, "circle", "椭圆 (O)"),
            (.arrow, "arrow.up.right", "箭头 (A)"),
            (.pen, "pencil.tip", "画笔 (P)"),
            (.polyline, "", "逐点连线 (L)"),
            (.mosaic, "", "马赛克 (M)"),
            (.redact, "rectangle.fill", "实心遮挡 (B)"),
            (.text, "textformat", "添加文字 (T)"),
            (.ocr, "text.viewfinder", "识别并选取文字 (X)")
        ]
        for (tool, icon, title) in tools {
            let button = iconButton(icon, title, #selector(chooseTool))
            if tool == .mosaic || tool == .polyline {
                button.image = toolIcon(tool, title: title)
            }
            button.setButtonType(.pushOnPushOff)
            button.tag = tool.rawValue
            toolButtons[tool] = button
            controls.addArrangedSubview(button)
        }
        controls.addArrangedSubview(iconButton("arrow.uturn.backward", "撤销 (⌘Z)", #selector(undoMark)))
        controls.addArrangedSubview(iconButton("arrow.uturn.forward", "重做 (⇧⌘Z)", #selector(redoMark)))
        controls.addArrangedSubview(saveButton)

        let dragImage = NSImage(systemSymbolName: "hand.draw", accessibilityDescription: "拖出 PNG") ?? NSImage()
        let drag = DragButton(image: dragImage, target: nil, action: nil)
        drag.toolTip = "按住拖到聊天窗口或桌面"
        drag.bezelStyle = .texturedRounded
        drag.refusesFirstResponder = true
        drag.startDrag = { [weak self] in self?.startDrag(with: $0) }
        controls.addArrangedSubview(drag)

        copyButton.bezelStyle = .rounded
        copyButton.refusesFirstResponder = true
        controls.addArrangedSubview(copyButton)
        controls.addArrangedSubview(iconButton("xmark", "取消 (Esc)", #selector(cancelCapture)))

        configureStyles()
        ocrControls.spacing = 8
        ocrControls.distribution = .gravityAreas
        ocrStatus.font = .systemFont(ofSize: 12)
        ocrControls.addView(ocrStatus, in: .trailing)
        ocrControls.addView(copyTextButton, in: .trailing)

        toolbarContent.orientation = .vertical
        toolbarContent.alignment = .trailing
        toolbarContent.spacing = 4
        toolbarContent.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        toolbarContent.addArrangedSubview(controls)
        toolbarContent.addArrangedSubview(styles)
        toolbarContent.addArrangedSubview(ocrControls)
        lineHelp.font = .systemFont(ofSize: 12)
        toolbarContent.addArrangedSubview(lineHelp)
        toolbar.addSubview(toolbarContent)
        toolbarContent.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            toolbarContent.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor),
            toolbarContent.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor),
            toolbarContent.topAnchor.constraint(equalTo: toolbar.topAnchor),
            toolbarContent.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor)
        ])
        addSubview(toolbar)
        setTool(.select)
    }

    private let colorNames = ["红色", "橙色", "绿色", "蓝色", "白色", "黑色"]
    private var palette: [NSColor] {
        [NSColor(srgbRed: 1, green: 0.24, blue: 0.20, alpha: 1), .systemOrange,
         .systemGreen, .systemBlue, .white, .black]
    }
    private let widths: [CGFloat] = [2, 3, 6]
    private let sizePicker = NSSegmentedControl()
    private lazy var linePicker = stylePicker(["实线", "虚线"], label: "线段样式", action: #selector(chooseLineStyle))
    private lazy var arrowPicker = stylePicker(["等粗", "渐粗"], label: "箭头样式", action: #selector(chooseArrowShape))
    private var usesTextSizes: Bool { tool == .text || textEditor != nil }
    private var displayedWidths: [CGFloat] { usesTextSizes ? Array(widths.reversed()) : widths }

    private func configureStyles() {
        styles.spacing = 5
        styles.distribution = .gravityAreas
        for (index, color) in palette.enumerated() {
            let name = colorNames[index]
            let button = NSButton(image: swatchImage(color, name: name, selected: false),
                                  target: self, action: #selector(chooseColor))
            button.alternateImage = swatchImage(color, name: name, selected: true)
            button.bezelStyle = .texturedRounded
            button.toolTip = name
            button.setAccessibilityLabel(name)
            button.refusesFirstResponder = true
            button.setButtonType(.pushOnPushOff)
            button.tag = index
            button.state = index == 0 ? .on : .off
            colorButtons.append(button)
            styles.addView(button, in: .trailing)
        }
        sizePicker.segmentCount = widths.count
        sizePicker.selectedSegment = 1
        sizePicker.target = self
        sizePicker.action = #selector(chooseSize)
        sizePicker.refusesFirstResponder = true
        styles.addView(sizePicker, in: .trailing)
        styles.addView(linePicker, in: .trailing)
        styles.addView(arrowPicker, in: .trailing)
    }

    private func stylePicker(_ labels: [String], label: String, action: Selector) -> NSSegmentedControl {
        let picker = NSSegmentedControl(labels: labels, trackingMode: .selectOne, target: self, action: action)
        picker.setAccessibilityLabel(label)
        picker.toolTip = label
        picker.refusesFirstResponder = true
        return picker
    }

    @objc private func chooseLineStyle() {
        guard let style = CaptureLineStyle(rawValue: linePicker.selectedSegment) else { return }
        lineStyle = style
        if !linePoints.isEmpty { needsDisplay = true }
    }

    @objc private func chooseArrowShape() {
        guard let shape = CaptureArrowShape(rawValue: arrowPicker.selectedSegment) else { return }
        arrowShape = shape
    }

    private func swatchImage(_ color: NSColor, name: String, selected: Bool) -> NSImage {
        let image = NSImage(size: CGSize(width: 26, height: 17), flipped: false) { rect in
            let swatch = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 3, yRadius: 3)
            color.setFill()
            swatch.fill()
            NSColor.labelColor.withAlphaComponent(0.55).setStroke()
            swatch.stroke()
            if selected {
                let check = NSBezierPath()
                check.move(to: CGPoint(x: 8, y: 8))
                check.line(to: CGPoint(x: 11, y: 5))
                check.line(to: CGPoint(x: 17, y: 12))
                check.lineCapStyle = .round
                check.lineJoinStyle = .round
                NSColor.white.setStroke()
                check.lineWidth = 4
                check.stroke()
                NSColor.black.setStroke()
                check.lineWidth = 1.6
                check.stroke()
            }
            return true
        }
        image.accessibilityDescription = name
        return image
    }

    private func toolIcon(_ tool: CaptureTool, title: String) -> NSImage {
        let image = NSImage(size: CGSize(width: 18, height: 18), flipped: false) { _ in
            if tool == .mosaic {
                let tones: [[CGFloat]] = [[0.85, 0.32, 0.6], [0.48, 1, 0.32], [0.68, 0.48, 0.87]]
                for (row, cells) in tones.enumerated() {
                    for (column, tone) in cells.enumerated() {
                        NSColor.labelColor.withAlphaComponent(tone).setFill()
                        NSBezierPath(rect: CGRect(x: 1 + 6 * column, y: 1 + 6 * row, width: 4, height: 4)).fill()
                    }
                }
            } else {
                let points = [CGPoint(x: 3, y: 4), CGPoint(x: 8, y: 14), CGPoint(x: 15, y: 8)]
                let path = NSBezierPath()
                path.move(to: points[0])
                path.line(to: points[1])
                path.line(to: points[2])
                NSColor.labelColor.set()
                path.lineWidth = 1.5
                path.stroke()
                for point in points {
                    NSBezierPath(ovalIn: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4)).fill()
                }
            }
            return true
        }
        image.accessibilityDescription = title
        return image
    }

    private func makeCopyTextButton() -> NSButton {
        let button = NSButton(title: "复制文字", target: self, action: #selector(copyText))
        button.bezelStyle = .rounded
        button.refusesFirstResponder = true
        button.isEnabled = false
        return button
    }

    @objc private func chooseColor(_ button: NSButton) {
        let color = palette[button.tag]
        if tool == .redact {
            maskColor = color
        } else {
            annotationColor = color
            editingText?.color = color
            textEditor?.textColor = color
        }
        refreshStyleControls()
        if !linePoints.isEmpty { needsDisplay = true }
    }

    @objc private func chooseSize() {
        guard displayedWidths.indices.contains(sizePicker.selectedSegment) else { return }
        let width = displayedWidths[sizePicker.selectedSegment]
        if usesTextSizes {
            textWidth = width
            editingText?.width = width
            textEditor?.font = CaptureMark.font(for: width)
            layoutTextEditor()
        } else {
            annotationWidth = width
        }
        if !linePoints.isEmpty { needsDisplay = true }
    }

    private func refreshStyleControls() {
        let color = tool == .redact ? maskColor : annotationColor
        for (index, swatch) in colorButtons.enumerated() { swatch.state = palette[index] == color ? .on : .off }
        let labels = usesTextSizes ? ["大", "中", "小"] : ["细", "中", "粗"]
        for (index, label) in labels.enumerated() { sizePicker.setLabel(label, forSegment: index) }
        let width = usesTextSizes ? textWidth : annotationWidth
        sizePicker.selectedSegment = displayedWidths.firstIndex(of: width) ?? 1
        sizePicker.isHidden = tool == .redact
        linePicker.isHidden = !tool.usesLineStyle
        linePicker.selectedSegment = lineStyle.rawValue
        arrowPicker.isHidden = tool != .arrow
        arrowPicker.selectedSegment = arrowShape.rawValue
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    func refreshWindowSuggestion() {
        guard let window else { return }
        updateWindowSuggestion(at: convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }

    private func windowSuggestion(at point: CGPoint) -> CGRect? {
        windowSuggestions.first { $0.contains(point) }
    }

    private func updateWindowSuggestion(at point: CGPoint) {
        let next = selection.isEmpty && anchor == nil ? windowSuggestion(at: point) : nil
        guard suggestedWindow != next else { return }
        suggestedWindow = next
        needsDisplay = true
    }

    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        updateWindowSuggestion(at: point)
        if !linePoints.isEmpty {
            lineHover = selection.contains(point) ? point : nil
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        suggestedWindow = nil
        lineHover = nil
        needsDisplay = true
    }

    private func iconButton(_ symbol: String, _ title: String, _ action: Selector) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: title) ?? NSImage()
        let button = NSButton(image: image, target: self, action: action)
        button.bezelStyle = .texturedRounded
        button.toolTip = title
        button.refusesFirstResponder = true
        return button
    }

    private func updateToolbar() {
        guard selection.width >= 2, selection.height >= 2, anchor == nil else {
            toolbar.isHidden = true
            return
        }
        let wasHidden = toolbar.isHidden
        let size = toolbarContent.fittingSize
        let lower = selection.maxY + 9
        let upper = selection.minY - size.height - 9
        let y = lower + size.height <= bounds.height - 8 ? lower : max(8, upper)
        let frame = CGRect(x: max(8, min(selection.maxX - size.width, bounds.width - size.width - 8)),
                           y: y, width: size.width, height: size.height)
        if toolbar.frame != frame { toolbar.frame = frame }
        guard wasHidden else { return }
        toolbar.isHidden = false
        if wasHidden && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            toolbar.alphaValue = 0.76
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.13
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                toolbar.animator().alphaValue = 1
            }
        } else {
            toolbar.alphaValue = 1
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        NSColor.black.withAlphaComponent(dark ? 0.52 : 0.36).setFill()
        let shade = NSBezierPath(rect: bounds)
        shade.appendRect(selection.isEmpty ? (suggestedWindow ?? .zero) : selection)
        shade.windingRule = .evenOdd
        shade.fill()

        guard !selection.isEmpty, let context = NSGraphicsContext.current?.cgContext else {
            if let suggestedWindow, anchor == nil {
                NSColor.systemBlue.setStroke()
                let outline = NSBezierPath(rect: suggestedWindow.insetBy(dx: 1, dy: 1))
                outline.lineWidth = 2
                outline.stroke()
                drawBadge("点击截取此窗口 · 拖动可手动框选",
                          center: CGPoint(x: suggestedWindow.midX, y: max(16, suggestedWindow.minY + 19)))
            } else if anchor == nil {
                drawBadge("拖动框选截图区域  ·  Esc 取消",
                          center: CGPoint(x: bounds.midX, y: bounds.height * 0.24))
            }
            return
        }

        context.saveGState()
        context.clip(to: selection)
        drawMarks(in: context, includingDraft: true)
        if !linePoints.isEmpty { drawLinePreview(in: context) }
        if tool == .ocr { drawTextSelection(in: context) }
        if tool == .pointer, let selectedMark, marks.indices.contains(selectedMark), editingMark == nil {
            context.setStrokeColor(NSColor.systemBlue.cgColor)
            context.setLineWidth(1)
            context.setLineDash(phase: 0, lengths: [4, 3])
            context.stroke(marks[selectedMark].visualBounds.insetBy(dx: -4, dy: -4))
        }
        context.restoreGState()

        let edge = NSBezierPath(rect: selection)
        NSColor.black.withAlphaComponent(0.42).setStroke()
        edge.lineWidth = 3
        edge.stroke()
        NSColor.white.withAlphaComponent(0.95).setStroke()
        edge.lineWidth = 1
        edge.stroke()

        if anchor == nil, tool == .select, min(selection.width, selection.height) >= 14 {
            for xDirection in [-1.0, 1.0] {
                for yDirection in [-1.0, 1.0] {
                    let x = xDirection > 0 ? selection.minX : selection.maxX
                    let y = yDirection > 0 ? selection.minY : selection.maxY
                    let corner = NSBezierPath()
                    corner.move(to: CGPoint(x: x + 9 * xDirection, y: y))
                    corner.line(to: CGPoint(x: x, y: y))
                    corner.line(to: CGPoint(x: x, y: y + 9 * yDirection))
                    corner.lineCapStyle = .round
                    corner.lineJoinStyle = .round
                    corner.lineWidth = 3
                    corner.stroke()
                }
            }
        }

        if anchor != nil {
            let scaleX = CGFloat(screenshot.width) / bounds.width
            let scaleY = CGFloat(screenshot.height) / bounds.height
            let width = Int((selection.width * scaleX).rounded())
            let height = Int((selection.height * scaleY).rounded())
            let y = selection.minY >= 38 ? selection.minY - 19 : min(bounds.maxY - 17, selection.maxY + 19)
            drawBadge("\(width) × \(height) px", center: CGPoint(x: selection.midX, y: y))
        }
    }

    private func drawMarks(in context: CGContext, includingDraft: Bool) {
        var visible = marks
        if includingDraft {
            if let editingMark { visible.remove(at: editingMark) }
            if let draft { visible.append(draft) }
            if let line = polylineMark() { visible.append(line) }
        }
        for mark in visible where mark.tool != .redact {
            context.saveGState()
            if mark.tool == .mosaic {
                context.clip(to: mark.box)
                if let mosaic {
                    context.interpolationQuality = .none
                    context.translateBy(x: 0, y: bounds.height)
                    context.scaleBy(x: 1, y: -1)
                    context.draw(mosaic, in: bounds)
                } else {
                    context.setFillColor(gray: 0, alpha: 1)
                    context.fill(bounds)
                }
            } else {
                mark.drawBody(in: context)
            }
            context.restoreGState()
        }

        // Draw solid covers last so an overlapping mosaic cannot expose covered pixels.
        context.saveGState()
        context.setShouldAntialias(false)
        for mark in visible where mark.tool == .redact && !mark.box.isEmpty {
            context.setFillColor(mark.color.withAlphaComponent(1).cgColor)
            let pixels = context.convertToDeviceSpace(mark.box).standardized.integral
            context.fill(context.convertToUserSpace(pixels).standardized)
        }
        context.restoreGState()
    }

    private func drawTextSelection(in context: CGContext) {
        guard let textLines else { return }
        context.setLineWidth(1)
        context.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.8).cgColor)
        context.setFillColor(NSColor.systemBlue.withAlphaComponent(0.4).cgColor)
        for (index, line) in textLines.enumerated() {
            context.stroke(line.bounds.insetBy(dx: -1, dy: -1))
            if let range = selectedCharacters(in: index, count: line.boxes.count) {
                for box in line.boxes[range] { context.fill(box) }
            }
        }
    }

    private func drawBadge(_ text: String, center: CGPoint) {
        let label = text as NSString
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: dark ? NSColor.white : NSColor.black
        ]
        let size = label.size(withAttributes: attributes)
        let badgeWidth = ceil(size.width) + 24
        let x = min(max(center.x - badgeWidth / 2, 8), max(8, bounds.maxX - badgeWidth - 8))
        let frame = CGRect(x: x, y: center.y - 13, width: badgeWidth, height: 26)
        let background = NSBezierPath(roundedRect: frame, xRadius: 13, yRadius: 13)
        NSColor(white: dark ? 0.12 : 1, alpha: 0.94).setFill()
        background.fill()
        NSColor(white: dark ? 1 : 0, alpha: 0.15).setStroke()
        background.stroke()
        label.draw(at: CGPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2),
                   withAttributes: attributes)
    }

    private func point(for event: NSEvent, in limit: CGRect) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: min(max(point.x, limit.minX), limit.maxX),
                       y: min(max(point.y, limit.minY), limit.maxY))
    }

    override func mouseDown(with event: NSEvent) {
        guard !isEncodingPNG else { return }
        let location = point(for: event, in: bounds)
        finishText()
        if tool != .select {
            guard selection.contains(location) else { return }
            switch tool {
            case .polyline:
                addLinePoint(at: location, finishing: event.clickCount > 1)
            case .text:
                startText(at: location, existing: mark(at: location, textOnly: true))
            case .pointer:
                selectedMark = mark(at: location)
                if let selectedMark {
                    if event.clickCount == 2, marks[selectedMark].tool == .text {
                        startText(at: location, existing: selectedMark)
                    } else {
                        movingMark = (selectedMark, location, marks)
                    }
                }
            case .ocr:
                textAnchor = textPosition(at: location, requireHit: true)
                textEnd = textAnchor
                updateTextControls()
            default:
                draft = CaptureMark(tool: tool, start: location, end: location,
                                    color: tool == .redact ? maskColor : annotationColor, width: annotationWidth,
                                    lineStyle: lineStyle, arrowShape: arrowShape)
            }
            needsDisplay = true
            return
        }

        invalidateRecognition()
        selectedMark = nil
        clickedWindow = selection.isEmpty ? windowSuggestion(at: location) : nil
        suggestedWindow = nil
        let near = selection.insetBy(dx: -7, dy: -7).contains(location)
        let edgeX = abs(location.x - selection.minX) < 7 || abs(location.x - selection.maxX) < 7
        let edgeY = abs(location.y - selection.minY) < 7 || abs(location.y - selection.maxY) < 7
        resizing = !selection.isEmpty && near && (edgeX || edgeY)
        if !resizing {
            anchor = location
            selection = .zero
            marks.removeAll()
            undoMarks.removeAll()
            redoMarks.removeAll()
        } else {
            let fixedX = abs(location.x - selection.minX) < abs(location.x - selection.maxX) ? selection.maxX : selection.minX
            let fixedY = abs(location.y - selection.minY) < abs(location.y - selection.maxY) ? selection.maxY : selection.minY
            anchor = CGPoint(x: edgeX ? fixedX : location.x, y: edgeY ? fixedY : location.y)
        }
        resizeStart = selection
        resizeAxes = (edgeX, edgeY)
        updateToolbar()
        needsDisplay = true
    }

    private var resizeStart = CGRect.zero
    private var resizeAxes = (x: false, y: false)

    override func mouseDragged(with event: NSEvent) {
        if let anchor {
            if clickedWindow != nil {
                let point = point(for: event, in: bounds)
                guard hypot(point.x - anchor.x, point.y - anchor.y) >= 4 else { return }
                clickedWindow = nil
            }
            var next = selectionRect(from: anchor, to: point(for: event, in: bounds))
            if resizing {
                if !resizeAxes.x { next.origin.x = resizeStart.minX; next.size.width = resizeStart.width }
                if !resizeAxes.y { next.origin.y = resizeStart.minY; next.size.height = resizeStart.height }
            }
            selection = next
        } else if let movingMark {
            let previous = marks[movingMark.index].visualBounds
            let point = point(for: event, in: selection)
            let original = movingMark.before[movingMark.index]
            let box = original.visualBounds
            func clamp(_ value: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
                min(max(value, min(0, minimum)), max(0, maximum))
            }
            let delta = CGPoint(x: clamp(point.x - movingMark.origin.x, minimum: selection.minX - box.minX,
                                         maximum: selection.maxX - box.maxX),
                                y: clamp(point.y - movingMark.origin.y, minimum: selection.minY - box.minY,
                                         maximum: selection.maxY - box.maxY))
            marks[movingMark.index] = original
            marks[movingMark.index].move(by: delta)
            invalidateOverlay(previous.union(marks[movingMark.index].visualBounds))
            return
        } else if let draftTool = draft?.tool, let previousPoint = draft?.end {
            let point = point(for: event, in: selection)
            guard point != previousPoint else { return }
            if draftTool == .pen, let start = draft?.start, let width = draft?.width {
                appendPenPoint(point, previous: previousPoint, start: start)
                invalidateOverlay(selectionRect(from: previousPoint, to: point).insetBy(dx: -width, dy: -width))
            } else {
                let previous = draft?.visualBounds ?? .null
                draft?.end = point
                if let draft { invalidateOverlay(previous.union(draft.visualBounds)) }
            }
            return
        } else if tool == .ocr, textAnchor != nil {
            let end = textPosition(at: point(for: event, in: selection), requireHit: false)
            guard end != textEnd else { return }
            textEnd = end
            copyTextButton.isEnabled = end != nil
            invalidateOverlay(selection)
            return
        }
        needsDisplay = true
    }

    private func appendPenPoint(_ point: CGPoint, previous: CGPoint, start: CGPoint) {
        if previous != start || draft?.points.isEmpty == false { draft?.points.append(previous) }
        draft?.end = point
    }

    private func invalidateOverlay(_ region: CGRect) {
        let dirty = region.insetBy(dx: -7, dy: -7).intersection(bounds)
        if !dirty.isEmpty { setNeedsDisplay(dirty) }
    }

    override func mouseUp(with event: NSEvent) {
        if anchor != nil, resizing, (selection.width < 2 || selection.height < 2) {
            selection = resizeStart
        }
        anchor = nil
        if let clickedWindow {
            selection = clickedWindow
            self.clickedWindow = nil
        }
        if let movingMark {
            self.movingMark = nil
            if marks[movingMark.index].start != movingMark.before[movingMark.index].start {
                recordEdit(previous: movingMark.before)
            }
        }
        if var mark = draft {
            let end = point(for: event, in: selection)
            if mark.tool == .pen, end != mark.end, mark.end != mark.start {
                mark.points.append(mark.end)
            }
            mark.end = end
            let hasLength = hypot(mark.end.x - mark.start.x, mark.end.y - mark.start.y) >= 2
            let isArea = [.rectangle, .ellipse, .mosaic, .redact].contains(mark.tool)
            if isArea ? !mark.box.isEmpty : (hasLength || !mark.points.isEmpty) {
                addMark(mark)
            }
            draft = nil
        }
        updateToolbar()
        needsDisplay = true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .control, .option])
        if textEditor == nil {
            switch (modifiers, event.charactersIgnoringModifiers?.lowercased()) {
            case (.command, "z"): undoMark(); return true
            case ([.command, .shift], "z"): redoMark(); return true
            case (.command, "c"):
                if tool == .ocr { copyText() } else { copyImage() }
                return true
            case (.command, "a") where tool == .ocr:
                selectAllText()
                return true
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        guard modifiers.isEmpty else { super.keyDown(with: event); return }
        switch event.keyCode {
        case 53:
            if linePoints.isEmpty { cancelCapture() } else { clearLine() }
        case 36, 76:
            if !linePoints.isEmpty { finishLine() }
            else if tool == .ocr { copyText() }
            else { copyImage() }
        default:
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "v": setTool(.select)
            case "s": setTool(.pointer)
            case "r": setTool(.rectangle)
            case "o": setTool(.ellipse)
            case "a": setTool(.arrow)
            case "p": setTool(.pen)
            case "l": setTool(.polyline)
            case "m": setTool(.mosaic)
            case "b": setTool(.redact)
            case "t": setTool(.text)
            case "x": setTool(.ocr)
            default: super.keyDown(with: event)
            }
        }
    }

    private func setTool(_ tool: CaptureTool) {
        guard !isEncodingPNG, tool == .select || (!toolbar.isHidden && anchor == nil) else { return }
        if tool != self.tool {
            finishText()
            finishLine()
        }
        if tool != .pointer { selectedMark = nil }
        self.tool = tool
        for (kind, button) in toolButtons { button.state = kind == tool ? .on : .off }
        styles.isHidden = !tool.usesStyle && textEditor == nil
        ocrControls.isHidden = tool != .ocr
        lineHelp.isHidden = tool != .polyline
        refreshStyleControls()
        if tool == .ocr {
            recognizeText()
            updateTextControls()
        }
        updateToolbar()
        needsDisplay = true
    }

    @objc private func chooseTool(_ sender: NSButton) {
        if let tool = CaptureTool(rawValue: sender.tag) { setTool(tool) }
    }

    @objc private func cancelCapture() { onClose?(true) }

    private func addLinePoint(at point: CGPoint, finishing: Bool) {
        if let last = linePoints.last, hypot(point.x - last.x, point.y - last.y) < 2 {
            if finishing, linePoints.count >= 2 { finishLine() }
            return
        }
        linePoints.append(point)
        lineHover = nil
        if finishing, linePoints.count >= 2 { finishLine() }
    }

    private func polylineMark() -> CaptureMark? {
        guard linePoints.count >= 2, let start = linePoints.first, let end = linePoints.last else { return nil }
        return CaptureMark(tool: .polyline, start: start, end: end, color: annotationColor,
                           width: annotationWidth, points: Array(linePoints.dropFirst().dropLast()), lineStyle: lineStyle)
    }

    private func drawLinePreview(in context: CGContext) {
        guard let last = linePoints.last else { return }
        context.saveGState()
        if let lineHover {
            context.setStrokeColor(annotationColor.withAlphaComponent(0.7).cgColor)
            context.setLineWidth(annotationWidth)
            context.setLineDash(phase: 0, lengths: [5, 4])
            context.move(to: last)
            context.addLine(to: lineHover)
            context.strokePath()
        }
        context.setFillColor(annotationColor.cgColor)
        for point in linePoints {
            context.fillEllipse(in: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6))
        }
        context.restoreGState()
    }

    private func clearLine() {
        linePoints.removeAll()
        lineHover = nil
        needsDisplay = true
    }

    private func finishLine() {
        guard !linePoints.isEmpty else { return }
        if let line = polylineMark() { addMark(line) }
        clearLine()
    }

    private func mark(at point: CGPoint, textOnly: Bool = false) -> Int? {
        if !textOnly, let cover = marks.indices.reversed().first(where: {
            marks[$0].tool == .redact && marks[$0].box.contains(point)
        }) { return cover }
        let top = marks.indices.reversed()
        if let hit = top.first(where: { (!textOnly || marks[$0].tool == .text) && marks[$0].contains(point) }) {
            return hit
        }
        guard !textOnly else { return nil }
        return top.first {
            let mark = marks[$0]
            switch mark.tool {
            case .rectangle: return mark.box.contains(point)
            case .ellipse: return CGPath(ellipseIn: mark.box, transform: nil).contains(point)
            default: return false
            }
        }
    }

    private func addMark(_ mark: CaptureMark) {
        recordEdit(previous: marks)
        marks.append(mark)
        ScreenshotUsage.annotated.record()
    }

    private func recordEdit(previous: [CaptureMark]) {
        undoMarks.append(previous)
        redoMarks.removeAll()
        invalidateRecognition()
    }

    @objc private func undoMark() {
        guard !isEncodingPNG else { return }
        if !linePoints.isEmpty {
            linePoints.removeLast()
            lineHover = nil
            needsDisplay = true
            return
        }
        finishText()
        guard let previous = undoMarks.popLast() else { return }
        redoMarks.append(marks)
        marks = previous
        refreshAfterEdit()
    }

    @objc private func redoMark() {
        guard !isEncodingPNG, linePoints.isEmpty else { return }
        finishText()
        guard let next = redoMarks.popLast() else { return }
        undoMarks.append(marks)
        marks = next
        refreshAfterEdit()
    }

    private func refreshAfterEdit() {
        selectedMark = nil
        invalidateRecognition()
        if tool == .ocr { recognizeText() }
        needsDisplay = true
    }

    private func startText(at location: CGPoint, existing: Int?) {
        let origin = CGPoint(x: min(location.x, max(selection.minX + 3, selection.maxX - 85)),
                             y: min(location.y, max(selection.minY + 3, selection.maxY - 32)))
        var mark = existing.map { marks[$0] } ?? CaptureMark(tool: .text, start: origin, end: origin,
                                                             color: annotationColor, width: textWidth)
        let availableWidth = max(1, selection.maxX - mark.start.x - 4)
        mark.textWidth = mark.textWidth > 0 ? min(mark.textWidth, availableWidth) : availableWidth
        let editor = CaptureTextEditor(frame: .zero)
        editor.isRichText = false
        editor.drawsBackground = false
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.textContainerInset = .zero
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainer?.widthTracksTextView = true
        editor.isVerticallyResizable = true
        editor.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainer?.containerSize.height = CGFloat.greatestFiniteMagnitude
        editor.autoresizingMask = [.width]
        editor.font = CaptureMark.font(for: mark.width)
        editor.textColor = mark.color
        editor.insertionPointColor = .controlAccentColor
        editor.string = mark.text
        editor.delegate = self
        editor.onFinish = { [weak self] commit in self?.finishText(commit: commit) }
        editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))

        let box = NSScrollView(frame: .zero)
        box.drawsBackground = false
        box.contentView.drawsBackground = false
        box.wantsLayer = true
        box.layer?.borderWidth = 1
        box.layer?.borderColor = NSColor.controlAccentColor.cgColor
        box.documentView = editor
        textEditor = editor
        textBox = box
        editingMark = existing
        editingText = mark
        annotationColor = mark.color
        textWidth = mark.width
        refreshStyleControls()
        styles.isHidden = false
        updateToolbar()
        addSubview(box, positioned: .below, relativeTo: toolbar)
        layoutTextEditor()
        window?.makeFirstResponder(editor)
        if existing != nil {
            let index = editor.characterIndexForInsertion(at: editor.convert(location, from: self))
            editor.setSelectedRange(NSRange(location: index, length: 0))
        }
    }

    private func layoutTextEditor() {
        guard let editor = textEditor, let box = textBox, var mark = editingText else { return }
        mark.text = editor.string + " "
        let font = CaptureMark.font(for: mark.width)
        let height = max(ceil(font.ascender - font.descender + font.leading), mark.visualBounds.height)
        let availableHeight = max(1, selection.maxY - mark.start.y)
        box.frame = CGRect(x: mark.start.x, y: mark.start.y, width: mark.textWidth,
                           height: min(height + 4, availableHeight))
        editor.frame.size = CGSize(width: box.contentSize.width, height: height)
        editor.minSize = CGSize(width: 0, height: box.contentSize.height)
        editor.scrollRangeToVisible(editor.selectedRange())
    }

    func textDidChange(_ notification: Notification) { layoutTextEditor() }

    private func finishText(commit: Bool = true) {
        guard let editor = textEditor, var mark = editingText else { return }
        if editor.hasMarkedText() { editor.unmarkText() }
        mark.text = editor.string
        let index = editingMark
        editor.delegate = nil
        textEditor = nil
        editingText = nil
        editingMark = nil
        if window?.firstResponder === editor { window?.makeFirstResponder(self) }
        textBox?.removeFromSuperview()
        textBox = nil
        if commit {
            let empty = mark.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if let index {
                if empty || mark.text != marks[index].text || mark.color != marks[index].color || mark.width != marks[index].width {
                    recordEdit(previous: marks)
                    if empty {
                        marks.remove(at: index)
                        selectedMark = nil
                    } else {
                        marks[index] = mark
                    }
                }
            } else if !empty {
                addMark(mark)
            }
        }
        styles.isHidden = !tool.usesStyle
        refreshStyleControls()
        updateToolbar()
        needsDisplay = true
    }

    private func invalidateRecognition() {
        recognitionID = nil
        textLines = nil
        textAnchor = nil
        textEnd = nil
        copyTextButton.isEnabled = false
    }

    private func recognizeText() {
        guard textLines == nil, recognitionID == nil else { return }
        guard let (image, frame) = renderedSelection() else {
            ocrStatus.stringValue = "无法识别文字，按 X 重试"
            return
        }
        let id = UUID()
        recognitionID = id
        ocrStatus.stringValue = "正在识别文字…"
        DispatchQueue.global(qos: .userInitiated).async {
            let result = try? CaptureTextLine.recognize(in: image, frame: frame)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.recognitionID == id else { return }
                self.recognitionID = nil
                self.textLines = result
                if result != nil { ScreenshotUsage.ocrCompleted.record() }
                if self.tool == .ocr {
                    if result == nil { self.ocrStatus.stringValue = "识别失败，按 X 重试" }
                    self.updateTextControls()
                    self.needsDisplay = true
                }
            }
        }
    }

    private func textPosition(at point: CGPoint, requireHit: Bool) -> CaptureTextPosition? {
        guard let textLines else { return nil }
        func distance(to rect: CGRect) -> CGFloat {
            let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
            let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
            return hypot(dx, 2 * dy)
        }
        guard let line = textLines.indices.min(by: { distance(to: textLines[$0].bounds) < distance(to: textLines[$1].bounds) }),
              !requireHit || textLines[line].bounds.insetBy(dx: -5, dy: -5).contains(point),
              let character = textLines[line].boxes.indices.min(by: {
                  abs(textLines[line].boxes[$0].midX - point.x) < abs(textLines[line].boxes[$1].midX - point.x)
              }) else { return nil }
        return CaptureTextPosition(line: line, character: character)
    }

    private func selectedCharacters(in line: Int, count: Int) -> ClosedRange<Int>? {
        guard let textAnchor, let textEnd else { return nil }
        let start = min(textAnchor, textEnd)
        let end = max(textAnchor, textEnd)
        guard (start.line...end.line).contains(line) else { return nil }
        return (line == start.line ? start.character : 0)...(line == end.line ? end.character : count - 1)
    }

    private func selectAllText() {
        guard let textLines, let last = textLines.last else { return }
        textAnchor = CaptureTextPosition(line: 0, character: 0)
        textEnd = CaptureTextPosition(line: textLines.count - 1, character: last.characters.count - 1)
        updateTextControls()
        needsDisplay = true
    }

    private func updateTextControls() {
        copyTextButton.isEnabled = textEnd != nil
        if let textLines {
            ocrStatus.stringValue = textLines.isEmpty ? "未识别到文字" : "拖动选字 · ⌘A 全选 · ⌘C 复制"
        }
        updateToolbar()
    }

    private var selectedText: String {
        guard let textLines else { return "" }
        return textLines.enumerated().compactMap { index, line -> String? in
            guard let range = selectedCharacters(in: index, count: line.characters.count) else { return nil }
            return String(line.characters[range])
        }.joined(separator: "\n")
    }

    @objc private func copyText() {
        let text = selectedText
        guard !text.isEmpty else { NSSound.beep(); return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else { NSSound.beep(); return }
        ScreenshotUsage.ocrTextCopied.record()
        ocrStatus.stringValue = "已复制文字"
        updateToolbar()
    }

    @objc private func copyImage() {
        exportPNG { editor, data in
            let pasteboard = NSPasteboard.general
            let item = NSPasteboardItem()
            item.setData(data, forType: .png)
            pasteboard.clearContents()
            guard pasteboard.writeObjects([item]) else { NSSound.beep(); return }
            ScreenshotUsage.imageCopied.record()
            editor.onClose?(true)
        }
    }

    @objc private func save() {
        exportPNG { editor, data in editor.onSave?(data) }
    }

    private func exportPNG(_ completion: @escaping (CaptureView, Data) -> Void) {
        guard !isEncodingPNG, beginExport?() != false else { return }
        finishText()
        finishLine()
        guard let (image, _) = renderedSelection() else {
            endExport?()
            NSSound.beep()
            return
        }
        isEncodingPNG = true
        copyButton.isEnabled = false
        saveButton.isEnabled = false
        DispatchQueue.global(qos: .userInitiated).async {
            let data = Self.encodePNG(image)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isEncodingPNG = false
                self.copyButton.isEnabled = true
                self.saveButton.isEnabled = true
                self.endExport?()
                guard self.window?.isVisible == true else { return }
                guard let data else { NSSound.beep(); return }
                completion(self, data)
            }
        }
    }

    private func renderedSelection() -> (CGImage, CGRect)? {
        guard anchor == nil, selection.width >= 2, selection.height >= 2 else { return nil }
        let scaleX = CGFloat(screenshot.width) / bounds.width
        let scaleY = CGFloat(screenshot.height) / bounds.height
        let pixels = CGRect(x: selection.minX * scaleX, y: selection.minY * scaleY,
                            width: selection.width * scaleX, height: selection.height * scaleY).integral
            .intersection(CGRect(x: 0, y: 0, width: screenshot.width, height: screenshot.height))
        guard let cropped = screenshot.cropping(to: pixels) else { return nil }
        let frame = CGRect(x: pixels.minX / scaleX, y: pixels.minY / scaleY,
                           width: pixels.width / scaleX, height: pixels.height / scaleY)
        if marks.isEmpty { return (cropped, frame) }
        guard let context = CGContext(data: nil, width: cropped.width, height: cropped.height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: cropped.width, height: cropped.height))
        context.translateBy(x: -pixels.minX, y: pixels.maxY)
        context.scaleBy(x: scaleX, y: -scaleY)

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        drawMarks(in: context, includingDraft: false)
        return context.makeImage().map { ($0, frame) }
    }

    private func png() -> Data? {
        finishText()
        finishLine()
        guard !isEncodingPNG, let (result, _) = renderedSelection() else { return nil }
        return Self.encodePNG(result)
    }

    private static func encodePNG(_ result: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, result, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    private func startDrag(with event: NSEvent) {
        guard beginExport?() != false else { return }
        defer { endExport?() }
        guard let data = png(), let image = NSImage(data: data) else { NSSound.beep(); return }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenSnap-\(UUID().uuidString)", isDirectory: true)
        let file = directory.appendingPathComponent(screenshotName())
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            try data.write(to: file, options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            NSSound.beep()
            return
        }

        dragFolder = directory
        let item = NSDraggingItem(pasteboardWriter: file as NSURL)
        let factor = min(150 / max(selection.width, selection.height), 1)
        let size = CGSize(width: selection.width * factor, height: selection.height * factor)
        let location = convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(CGRect(x: location.x - size.width / 2, y: location.y - size.height / 2,
                                     width: size.width, height: size.height), contents: image)
        let session = beginDraggingSession(with: [item], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = false
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext)
        -> NSDragOperation { .copy }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        onDragVisibility?(false)
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        let folder = dragFolder
        dragFolder = nil
        if operation.isEmpty {
            if let folder { try? FileManager.default.removeItem(at: folder) }
            onDragVisibility?(true)
        } else {
            ScreenshotUsage.exported.record()
            // Some targets read the dropped URL asynchronously.
            if let folder {
                DispatchQueue.main.asyncAfter(deadline: .now() + 300) {
                    try? FileManager.default.removeItem(at: folder)
                }
            }
            onClose?(false)
        }
    }
}
