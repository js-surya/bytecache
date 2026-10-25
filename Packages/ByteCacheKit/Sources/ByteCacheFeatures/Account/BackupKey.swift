import ByteCacheCore
import Foundation

extension SessionManager {
    /// The name of the key that keeps this device signed in (CP-91), as it appears under API Keys in
    /// ByteStash: "ByteCache on iPhone, 2026-10-25". Western digits and the Gregorian calendar
    /// whatever the region, like the MCP key names.
    @MainActor
    public static func backupKeyName(on date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return "ByteCache on \(DeviceInfo.current.platform), \(formatter.string(from: date))"
    }
}
