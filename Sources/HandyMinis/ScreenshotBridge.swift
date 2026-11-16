@_cdecl("HandyMinisStartScreenshot")
func handyMinisStartScreenshot() {
    ScreenshotController.shared.startCapture()
}

@_cdecl("HandyMinisScreenshotIsActive")
func handyMinisScreenshotIsActive() -> Bool {
    ScreenshotController.shared.isActive
}
