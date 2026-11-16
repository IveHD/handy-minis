import AppKit

final class CaptureTextEditor: NSTextView {
    var onFinish: ((Bool) -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .control, .option])
        if modifiers == .command, event.keyCode == 36 || event.keyCode == 76 {
            onFinish?(true)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        if hasMarkedText() {
            super.cancelOperation(sender)
        } else {
            onFinish?(false)
        }
    }
}
