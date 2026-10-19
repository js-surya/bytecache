import Foundation
#if canImport(UIKit)
import CoreHaptics
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public enum HapticEvent: Sendable {
    /// A button press such as the scan shutter.
    case tap
    case success, error
    /// A choice changed, e.g. a toggle or picker in Settings.
    case selection
}

public enum HapticStrength: String, CaseIterable, Identifiable, Sendable {
    case light, medium, strong
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }

    public var intensity: Double {
        switch self {
        case .light: 0.4
        case .medium: 0.7
        case .strong: 1
        }
    }
}

@MainActor
public protocol HapticPlaying: AnyObject {
    func play(_ event: HapticEvent, intensity: Double)
    /// Warms up the hardware before an expected interaction, for lower latency.
    func prepare()
}

/// Every haptic in the app goes through here, so the user's setting always applies.
@MainActor
public enum Haptics {
    public static var player: any HapticPlaying = SystemHapticPlayer()
    private(set) static var enabled = true
    private(set) static var strength = HapticStrength.medium

    /// Called by `AppSettings` whenever the setting changes.
    public static func configure(enabled: Bool, strength: HapticStrength) {
        self.enabled = enabled
        self.strength = strength
    }

    public static func play(_ event: HapticEvent) {
        guard enabled else { return }
        player.play(event, intensity: strength.intensity)
    }

    public static func prepare() {
        guard enabled else { return }
        player.prepare()
    }
}

/// UIKit feedback generators on iPhone/iPad; the Force Touch trackpad on Mac. Does nothing on
/// hardware without haptics.
@MainActor
final class SystemHapticPlayer: HapticPlaying {
    #if canImport(UIKit)
    private let impact = UIImpactFeedbackGenerator(style: .medium)
    private let notification = UINotificationFeedbackGenerator()
    private let selection = UISelectionFeedbackGenerator()
    private let supported = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    func play(_ event: HapticEvent, intensity: Double) {
        guard supported else { return }
        switch event {
        case .tap: impact.impactOccurred(intensity: intensity)
        case .success: notification.notificationOccurred(.success)
        case .error: notification.notificationOccurred(.error)
        case .selection: selection.selectionChanged()
        }
    }

    func prepare() {
        guard supported else { return }
        impact.prepare()
        notification.prepare()
    }
    #elseif canImport(AppKit)
    func play(_ event: HapticEvent, intensity: Double) {
        let pattern: NSHapticFeedbackManager.FeedbackPattern = switch event {
        case .tap, .success: .levelChange
        case .error: .generic
        case .selection: .alignment
        }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }

    func prepare() {}
    #endif
}
