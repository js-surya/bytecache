import SwiftUI

/// ByteCache's loading animation, from the app icon: the ↓ arrow drops into the `{ }` braces,
/// which squeeze slightly as they catch it, then it fades into the box and the loop repeats.
/// Still (arrow resting inside) when Reduce Motion is on. Appears after a moment, so quick loads
/// don't flash it.
public struct LoadingMark: View {
    var caption: String?
    var size: CGFloat
    @State private var visible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ caption: String? = nil, size: CGFloat = 40) {
        self.caption = caption
        self.size = size
    }

    enum Phase: CaseIterable {
        case above, caught, inside

        var arrowOffset: CGFloat {
            switch self {
            case .above: -0.9
            case .caught: 0
            case .inside: 0.15
            }
        }

        var arrowOpacity: Double { self == .above ? 0 : self == .caught ? 1 : 0 }
        var bracesSqueeze: CGFloat { self == .caught ? 0.88 : 1 }
    }

    public var body: some View {
        VStack(spacing: 14) {
            Group {
                if reduceMotion {
                    mark(.caught)
                } else {
                    PhaseAnimator(Phase.allCases) { phase in
                        mark(phase)
                    } animation: { phase in
                        switch phase {
                        case .above: .easeIn(duration: 0.01)
                        case .caught: .spring(response: 0.42, dampingFraction: 0.62)
                        case .inside: .easeOut(duration: 0.45).delay(0.25)
                        }
                    }
                }
            }
            .frame(width: size * 2.2, height: size * 1.6)
            // The loop's animations would otherwise also move the mark from its first layout (the
            // top-left corner) when it appears during a tab switch.
            .geometryGroup()
            if let caption {
                Text(caption).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .opacity(visible ? 1 : 0)
        .task {
            try? await Task.sleep(for: .seconds(0.3))
            withAnimation(.easeOut(duration: 0.2)) { visible = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption ?? "Loading")
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func mark(_ phase: Phase) -> some View {
        HStack(spacing: size * 0.08) {
            brace("{")
            Image(systemName: "arrow.down")
                .font(.system(size: size * 0.62, weight: .bold))
                .offset(y: phase.arrowOffset * size)
                .opacity(phase.arrowOpacity)
                .frame(width: size * 0.55)
            brace("}")
        }
        .scaleEffect(x: phase.bracesSqueeze, y: 1)
        .foregroundStyle(.tint)
    }

    private func brace(_ text: String) -> some View {
        Text(text).font(.system(size: size, weight: .semibold, design: .rounded))
    }
}

#Preview {
    LoadingMark("Loading snippets…")
}
