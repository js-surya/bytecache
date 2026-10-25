import ByteCacheCore
import Foundation

extension SessionManager {
    /// The name of the key that keeps this device signed in (CP-91), as it appears under API Keys in
    /// ByteStash: "ByteCache on iPhone (iPhone18,2), 2026-10-25". The hardware model tells devices
    /// apart (iOS doesn't give apps the marketing name or, without an entitlement, the device's own
    /// name). Western digits and the Gregorian calendar whatever the region, like the MCP key names.
    @MainActor
    public static func backupKeyName(on date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        let device = DeviceInfo.current
        return "ByteCache on \(device.platform) (\(device.model)), \(formatter.string(from: date))"
    }
}

/// What "Stay signed in" does, in the same words wherever it can be turned on (CP-91). It makes an
/// API key on the user's account, so it's only done when they choose it.
public enum StaySignedInText {
    public static let title = "Stay Signed In"

    @MainActor
    public static var explanation: String {
        "Makes an API key for this device in your ByteStash account (“ByteCache on \(DeviceInfo.current.platform)”). "
            + "When the server ends your sign-in, after 24 hours by default, ByteCache carries on with that key "
            + "instead of asking you to sign in again. You'll see it under API Keys; turning this off deletes it."
    }

    public static let usingKey = "Your sign-in has ended, and ByteCache is using this device's key. Turning this off signs you out."
}
