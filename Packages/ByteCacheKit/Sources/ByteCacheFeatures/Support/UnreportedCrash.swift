import ByteCacheCore
import Foundation
import Observation

/// The crash waiting in Settings → Report a Bug, observable so the "Crash found" rows update the moment
/// it's reported or dismissed.
@MainActor @Observable
public final class UnreportedCrash {
    public static let shared = UnreportedCrash()

    /// When the unreported session ended, or nil.
    public private(set) var date: Date? = CrashWatch.shared.unreportedCrash

    /// Reported, or not wanted.
    public func clear() {
        CrashWatch.shared.clearUnreportedCrash()
        date = nil
    }
}
