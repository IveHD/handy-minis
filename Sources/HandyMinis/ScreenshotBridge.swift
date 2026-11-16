@_silgen_name("HandyMinisReportScreenshotUsage")
private func reportScreenshotUsage(_ event: UnsafePointer<CChar>)

@_cdecl("HandyMinisStartScreenshot")
func handyMinisStartScreenshot() {
    ScreenshotUsage.report = { event in
        event.rawValue.withCString { reportScreenshotUsage($0) }
    }
    ScreenshotController.shared.startCapture()
}

@_cdecl("HandyMinisScreenshotIsActive")
func handyMinisScreenshotIsActive() -> Bool {
    ScreenshotController.shared.isActive
}
