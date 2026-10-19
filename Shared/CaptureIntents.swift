import AppIntents
import ByteCatchCore

/// Opens ByteCatch with whatever was copied, ready to save. Used by the Control Center / Lock Screen
/// control, the Action Button and Siri. Compiled into both the app and the widget extension.
struct SaveClipboardIntent: AppIntent {
    static let title: LocalizedStringResource = "Save Clipboard to ByteCatch"
    static let description = IntentDescription("Opens ByteCatch with what you copied, ready to save as a snippet.")
    static var openAppWhenRun: Bool { true }

    func perform() async throws -> some IntentResult {
        PendingCapture.request(.captureClipboard)
        return .result()
    }
}
