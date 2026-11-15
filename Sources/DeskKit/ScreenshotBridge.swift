@_cdecl("DeskKitStartScreenshot")
func deskKitStartScreenshot() {
    ScreenshotController.shared.startCapture()
}

@_cdecl("DeskKitScreenshotIsActive")
func deskKitScreenshotIsActive() -> Bool {
    ScreenshotController.shared.isActive
}
