import AppIntents
import ByteCacheCore

/// Opens ByteCache with whatever was copied, ready to save. Used by the Control Center / Lock Screen
/// control, the Action Button and Siri. Compiled into both the app and the widget extension.
struct SaveClipboardIntent: AppIntent {
    static let title: LocalizedStringResource = "Save Clipboard to ByteCache"
    static let description = IntentDescription("Opens ByteCache with what you copied, ready to save as a snippet.")
    static var openAppWhenRun: Bool { true }

    func perform() async throws -> some IntentResult {
        PendingCapture.request(.captureClipboard)
        return .result()
    }
}

/// Opens ByteCache's Scan Code options (camera or photo on iPhone/iPad, image on Mac).
struct ScanCodeIntent: AppIntent {
    static let title: LocalizedStringResource = "Scan Code with ByteCache"
    static let description = IntentDescription("Opens ByteCache to scan code from the camera or a picture.")
    static var openAppWhenRun: Bool { true }

    func perform() async throws -> some IntentResult {
        PendingCapture.request(.scanCode)
        return .result()
    }
}
