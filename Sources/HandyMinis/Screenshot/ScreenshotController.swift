import AppKit
import ScreenCaptureKit
import UniformTypeIdentifiers

enum ScreenshotUsage: String {
    case started = "screenshot_started"
    case annotated = "screenshot_annotated"
    case ocrCompleted = "screenshot_ocr_completed"
    case ocrTextCopied = "screenshot_ocr_text_copied"
    case imageCopied = "screenshot_image_copied"
    case saved = "screenshot_saved"
    case exported = "screenshot_exported"

    static var report: ((Self) -> Void)?

    func record() { Self.report?(self) }
}

private final class CapturePanel: NSPanel {
    weak var editor: CaptureView?
    override var canBecomeKey: Bool { true }
}

private final class CaptureBackdrop: NSView {
    private let image: NSImage
    override var isOpaque: Bool { true }

    init(frame: CGRect, image: CGImage) {
        self.image = NSImage(cgImage: image, size: frame.size)
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: CGRect) {
        image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class ScreenshotController: NSObject {
    static let shared = ScreenshotController()

    private var panels: [CapturePanel] = []
    private var previousApp: NSRunningApplication?
    private var busy = false
    private var dragging = false
    private weak var exportingPanel: CapturePanel?
    var isActive: Bool { busy || !panels.isEmpty }

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidResignActive),
                                               name: NSApplication.didResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(displayConfigurationChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @objc private func applicationDidResignActive() {
        guard !busy, !dragging, !panels.isEmpty else { return }
        closeCapture(restore: false)
    }

    @objc private func displayConfigurationChanged() {
        guard !panels.isEmpty else { return }
        closeCapture(restore: false)
    }

    func openPermissions() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func startCapture() {
        guard !busy, !dragging else { return }
        if !panels.isEmpty {
            showPanels()
            return
        }
        busy = true
        previousApp = NSWorkspace.shared.frontmostApplication
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "HandyMinis"
            defer { busy = false }
            let alert = NSAlert()
            alert.messageText = "请允许 \(appName) 录制屏幕"
            alert.informativeText = "在系统设置中授权后，重新打开 \(appName)，再试一次。"
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "稍后")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                previousApp = nil
                openPermissions()
            }
            else { restoreFocus() }
            return
        }
        let screens = NSScreen.screens.compactMap { screen -> (NSScreen, CGDirectDisplayID)? in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return (screen, id.uint32Value)
        }
        let windowFrames = Self.visibleWindowFrames()
        Task { @MainActor in
            defer { busy = false }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                var captures: [CapturePanel] = []
                for (screen, id) in screens {
                    guard let display = content.displays.first(where: { $0.displayID == id }) else { continue }
                    let filter = SCContentFilter(display: display, excludingWindows: [])
                    if #available(macOS 14.2, *) { filter.includeMenuBar = true }
                    let configuration = SCStreamConfiguration()
                    configuration.width = Int((filter.contentRect.width * CGFloat(filter.pointPixelScale)).rounded())
                    configuration.height = Int((filter.contentRect.height * CGFloat(filter.pointPixelScale)).rounded())
                    configuration.showsCursor = false
                    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
                    let suggestions = Self.windowSuggestions(windowFrames, on: CGDisplayBounds(id), viewSize: screen.frame.size)
                    captures.append(makePanel(image, on: screen, suggestions: suggestions))
                }
                guard !captures.isEmpty else { throw CocoaError(.fileReadUnknown) }
                guard screens.allSatisfy({ original, id in
                    NSScreen.screens.contains {
                        let number = $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
                        return number?.uint32Value == id && $0.frame == original.frame
                    }
                }), NSScreen.screens.count == screens.count else {
                    previousApp = nil
                    return
                }
                panels = captures
                showPanels()
                ScreenshotUsage.started.record()
            } catch {
                showError("无法截取屏幕", detail: error.localizedDescription)
                restoreFocus()
            }
        }
    }

    private static func visibleWindowFrames() -> [CGRect] {
        // Quartz supplies these in front-to-back order, with a top-left desktop origin.
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.compactMap { window in
            guard window[kCGWindowLayer as String] as? Int == 0,
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let dictionary = window[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: dictionary as CFDictionary),
                  frame.width >= 40, frame.height >= 24 else { return nil }
            return frame
        }
    }

    static func windowSuggestions(_ frames: [CGRect], on display: CGRect, viewSize: CGSize) -> [CGRect] {
        guard !display.isEmpty else { return [] }
        let scaleX = viewSize.width / display.width
        let scaleY = viewSize.height / display.height
        return frames.compactMap { frame in
            let visible = frame.intersection(display)
            guard !visible.isEmpty else { return nil }
            return CGRect(x: (visible.minX - display.minX) * scaleX, y: (visible.minY - display.minY) * scaleY,
                          width: visible.width * scaleX, height: visible.height * scaleY)
        }
    }

    private func makePanel(_ image: CGImage, on screen: NSScreen, suggestions: [CGRect]) -> CapturePanel {
        let panel = CapturePanel(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.setFrame(screen.frame, display: false)
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.acceptsMouseMovedEvents = true

        let editor = CaptureView(frame: CGRect(origin: .zero, size: screen.frame.size), image: image,
                                 windowSuggestions: suggestions)
        editor.onClose = { [weak self] restore in self?.closeCapture(restore: restore) }
        editor.onSave = { [weak self, weak panel] data in
            if let panel { self?.save(data, from: panel) }
        }
        editor.beginExport = { [weak self, weak panel] in
            guard let self, let panel, self.panels.contains(panel),
                  self.exportingPanel == nil, !self.dragging, !self.busy else { return false }
            self.exportingPanel = panel
            return true
        }
        editor.endExport = { [weak self, weak panel] in
            guard let self, let panel, self.exportingPanel === panel else { return }
            self.exportingPanel = nil
        }
        editor.onDragVisibility = { [weak self, weak panel] visible in
            guard let self, let panel, self.panels.contains(panel) else { return }
            if visible {
                self.dragging = false
                self.showPanels(focusing: panel)
            } else {
                self.dragging = true
                self.panels.forEach { $0.orderOut(nil) }
            }
        }
        let container = NSView(frame: editor.frame)
        let backdrop = CaptureBackdrop(frame: container.bounds, image: image)
        backdrop.autoresizingMask = [.width, .height]
        editor.autoresizingMask = [.width, .height]
        editor.wantsLayer = true
        editor.layerContentsRedrawPolicy = .onSetNeedsDisplay
        container.addSubview(backdrop)
        container.addSubview(editor)
        panel.contentView = container
        panel.editor = editor
        panel.makeFirstResponder(editor)
        return panel
    }

    private func showPanels(focusing preferred: CapturePanel? = nil) {
        let cursor = NSEvent.mouseLocation
        guard let focus = preferred ?? panels.first(where: { $0.frame.contains(cursor) }) ?? panels.first else { return }
        NSApp.activate(ignoringOtherApps: true)
        for panel in panels where panel !== focus { panel.orderFront(nil) }
        focus.makeKeyAndOrderFront(nil)
        focus.editor?.refreshWindowSuggestion()
    }

    private func closeCapture(restore: Bool) {
        let closing = panels
        panels.removeAll()
        exportingPanel = nil
        dragging = false
        closing.forEach { $0.close() }
        if restore { restoreFocus() }
        else { previousApp = nil }
    }

    private func restoreFocus() {
        if let previousApp, previousApp != .current {
            previousApp.activate(options: [])
        }
        previousApp = nil
    }

    private func save(_ data: Data, from panel: CapturePanel) {
        guard !busy, panels.contains(panel) else { return }
        busy = true
        panels.forEach { $0.orderOut(nil) }
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = screenshotName()
        savePanel.begin { [weak self, weak panel] response in
            guard let self else { return }
            defer { self.busy = false }
            if response == .OK, let url = savePanel.url {
                do {
                    try data.write(to: url, options: .atomic)
                    ScreenshotUsage.saved.record()
                    self.closeCapture(restore: true)
                    return
                } catch {
                    self.showError("无法保存截图", detail: error.localizedDescription)
                }
            }
            if let panel, self.panels.contains(panel) { self.showPanels(focusing: panel) }
        }
    }

    private func showError(_ message: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

func screenshotName() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
    return "Screenshot \(formatter.string(from: Date())).png"
}
