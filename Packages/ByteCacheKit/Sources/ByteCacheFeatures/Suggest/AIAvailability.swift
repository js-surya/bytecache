import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Whether Apple Intelligence (the on-device model behind Suggest and Explain) can be used here, and
/// if not, why. Only Apple's own answer counts: ByteCache keeps no list of devices. Where Apple doesn't
/// say this device supports it (or can't be asked: systems before iOS / macOS 26) the features stay
/// hidden, with no promises. When Apple supports more devices its answer changes and they appear.
/// On supported devices that aren't set up yet, Settings says what's missing.
public enum AIAvailability: Equatable, Sendable {
    case available
    /// The system is older than iOS / iPadOS / macOS 26, which can't say whether the device supports it.
    case needsNewerSystem
    /// The hardware doesn't support Apple Intelligence.
    case deviceNotSupported
    /// Supported, but switched off in Settings.
    case turnedOff
    /// Supported and on, but the model is still downloading (or otherwise not ready yet).
    case notReady

    public static var current: AIAvailability {
        #if DEBUG
        // `-BCAIState turnedOff|notReady|deviceNotSupported|needsNewerSystem`: try each message (screenshots).
        if let state = UserDefaults.standard.string(forKey: "BCAIState"), let pretend = debugState(state) { return pretend }
        #endif
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return .available
            case .unavailable(.deviceNotEligible): return .deviceNotSupported
            case .unavailable(.appleIntelligenceNotEnabled): return .turnedOff
            case .unavailable(.modelNotReady): return .notReady
            case .unavailable: return .notReady
            }
        }
        return .needsNewerSystem
        #else
        return .deviceNotSupported
        #endif
    }

    #if DEBUG
    private static func debugState(_ name: String) -> AIAvailability? {
        switch name {
        case "turnedOff": .turnedOff
        case "notReady": .notReady
        case "deviceNotSupported": .deviceNotSupported
        case "needsNewerSystem": .needsNewerSystem
        default: nil
        }
    }
    #endif

    /// Hide the features: Apple doesn't say this device supports them.
    public var hidesFeatures: Bool { self == .deviceNotSupported || self == .needsNewerSystem }

    /// What to tell the person, or nil when it's available.
    public var explanation: String? {
        switch self {
        case .available: nil
        case .needsNewerSystem, .deviceNotSupported:
            // Hidden anyway; worded without promising support that Apple hasn't announced.
            "Smart Suggestions aren't available on this device."
        case .turnedOff:
            #if os(macOS)
            "Turn on Apple Intelligence in System Settings → Apple Intelligence & Siri to use Smart Suggestions."
            #else
            "Turn on Apple Intelligence in Settings → Apple Intelligence & Siri to use Smart Suggestions."
            #endif
        case .notReady:
            "Apple Intelligence is still getting ready on this device (it may be downloading). Try again in a little while."
        }
    }
}
