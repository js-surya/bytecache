import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Whether Apple Intelligence (the on-device model behind Suggest and Explain) can be used here, and
/// if not, why. Devices that can never run it (older iPhones and iPads, Intel Macs, systems before
/// iOS / macOS 26) don't show the features at all; on the others Settings says what's missing.
public enum AIAvailability: Equatable, Sendable {
    case available
    /// The system is older than iOS / iPadOS / macOS 26: an update would bring it.
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

    /// Hide the features: this device will never run them (a system update aside).
    public var hidesFeatures: Bool { self == .deviceNotSupported }

    /// What to tell the person, or nil when it's available.
    public var explanation: String? {
        switch self {
        case .available: nil
        case .needsNewerSystem:
            #if os(macOS)
            "Smart Suggestions use Apple Intelligence, which needs macOS 26 or later on a Mac with Apple silicon."
            #else
            "Smart Suggestions use Apple Intelligence, which needs iOS 26 or iPadOS 26 or later on a supported iPhone or iPad."
            #endif
        case .deviceNotSupported:
            #if os(macOS)
            "This Mac doesn't support Apple Intelligence."
            #else
            "This device doesn't support Apple Intelligence."
            #endif
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
