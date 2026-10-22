import SwiftUI

/// Feedback for every copy: a light haptic (honours the Haptics setting), a VoiceOver
/// announcement and a short "Copied" toast.
@MainActor
public enum CopyFeedback {
    /// The toast. The app shows it in its own overlay window so it's visible above sheets too;
    /// it stays empty in extensions.
    public static let toast = CopyToastModel()

    /// `toast: false` where the button already shows its own "Copied" label.
    public static func copied(_ message: String = "Copied", toast showToast: Bool = true) {
        Haptics.play(.selection)
        AccessibilityNotification.Announcement(message).post()
        if showToast { toast.show(message) }
    }
}

@MainActor @Observable
public final class CopyToastModel {
    public private(set) var message: String?
    public private(set) var symbol: AppSymbol = .check
    /// Called on every show with how long it stays, so the app can open its overlay window for that long.
    @ObservationIgnored public var onShow: ((Duration) -> Void)?
    private var hideTask: Task<Void, Never>?

    public init() {}

    public func show(_ message: String, symbol: AppSymbol = .check, for duration: Duration = .seconds(1.6)) {
        self.symbol = symbol
        self.message = message
        onShow?(duration)
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self.message = nil
        }
    }
}

/// Centred capsule at the top or bottom edge that slides in and out with the model's message.
public struct CopyToastLayer: View {
    let model: CopyToastModel
    let edge: VerticalEdge
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: CopyToastModel, edge: VerticalEdge = .bottom) {
        self.model = model
        self.edge = edge
    }

    public var body: some View {
        VStack {
            if edge == .bottom { Spacer() }
            if let message = model.message {
                Label(message, symbol: model.symbol)
                    .multilineTextAlignment(.center)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(.separator))
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                    // Longer messages wrap; keep them off the screen's edges.
                    .padding(.horizontal, 16)
                    .transition(reduceMotion ? .opacity : .move(edge: edge == .top ? .top : .bottom).combined(with: .opacity))
                    // Already announced by CopyFeedback.
                    .accessibilityHidden(true)
            }
            if edge == .top { Spacer() }
        }
        .padding(edge == .top ? .top : .bottom, edge == .top ? 4 : 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: model.message)
        .allowsHitTesting(false)
    }
}
