import SwiftUI

/// The Tip Jar in About: one row per tip with its App Store price. Hidden when the store has no tips
/// (for example before the products are approved), so About never shows a broken section. About
/// loads the model: a view that starts out empty never runs its own `.task`.
struct TipJarSection: View {
    @Bindable var model: TipJarModel

    var body: some View {
        if model.state == .ready {
            Section {
                VStack(spacing: 12) {
                    VStack(spacing: 2) {
                        Text("Tip Jar")
                            .font(.headline)
                        if model.isSupporter {
                            Text("Thank you for supporting ByteCache!")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .transition(.blurReplace)
                        } else {
                            Text("Enjoying ByteCache? Buy me a coffee.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .animation(.smooth, value: model.isSupporter)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    HStack(spacing: 10) {
                        ForEach(Array(model.tips.enumerated()), id: \.element.id) { index, tip in
                            TipButton(tip: tip, symbol: TipButton.symbols[min(index, 2)], buying: model.buying == tip.id,
                                      disabled: model.buying != nil) {
                                Task { await model.buy(tip) }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
                .overlay { TipBurst(trigger: model.celebrations) }
            } footer: {
                InfoFooter("ByteCache is free and open source. Tips are optional, unlock nothing and help keep it going.")
            }
            .alert("Waiting for Approval", isPresented: $model.showsPending) {
                Button("OK") {}
            } message: {
                Text("Your tip goes through once it's approved.")
            }
            .alert("Couldn't Send Tip", isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )) {
                Button("OK") {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }
}

extension TipJarModel {
    /// The App Store, or sample tips with `-BCTipJarPreview` (Debug builds).
    static func forAbout() -> TipJarModel {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-BCTipJarPreview") { return TipJarModel(store: PreviewTipStore()) }
        #endif
        return TipJarModel()
    }
}

/// One tip: a bigger coffee for a bigger tip, and the price underneath.
private struct TipButton: View {
    let tip: Tip
    let symbol: AppSymbol
    let buying: Bool
    let disabled: Bool
    let action: () -> Void

    static let symbols: [AppSymbol] = [.tipJar, .tipMedium, .tipLarge]

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Icon(symbol)
                .font(.body)
                .foregroundStyle(.orange)
                .frame(height: 22)
                .opacity(buying ? 0 : 1)
                .overlay { if buying { ProgressView().controlSize(.small) } }
                Text(tip.price)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel("\(tip.name), \(tip.price)")
    }
}

/// A coffee cup whose steam rises: the thank-you mark for people who tipped.
struct SteamingCup: View {
    var body: some View {
        Icon(.tipThanks)
            .foregroundStyle(.orange)
            .symbolEffect(.variableColor.iterative, options: .repeating)
            .accessibilityHidden(true)
    }
}

/// Cups and sparkles that rise and fade from the Tip Jar after a tip. Skipped with Reduce Motion.
private struct TipBurst: View {
    let trigger: Int
    @State private var pieces: [Piece] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Piece: Identifiable {
        let id = UUID()
        let symbol: AppSymbol
        let color: Color
        let size: CGFloat
        let x: CGFloat, y: CGFloat, spin: Double
        var flying = false
    }

    var body: some View {
        ZStack {
            ForEach(pieces) { piece in
                Icon(piece.symbol)
                    .font(.system(size: piece.size))
                    .foregroundStyle(piece.color)
                    .scaleEffect(piece.flying ? 1.1 : 0.3)
                    .rotationEffect(.degrees(piece.flying ? piece.spin : 0))
                    .offset(x: piece.flying ? piece.x : 0, y: piece.flying ? piece.y : 0)
                    .opacity(piece.flying ? 0 : 1)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) { burst() }
    }

    private func burst() {
        guard !reduceMotion else { return }
        let symbols: [AppSymbol] = [.tipJar, .tipMedium, .sparkles, .tipThanks]
        let colors: [Color] = [.orange, .yellow, .brown, .orange]
        pieces = (0..<18).map { i in
            Piece(symbol: symbols[i % symbols.count], color: colors[i % colors.count],
                  size: .random(in: 14...24), x: .random(in: -160...160), y: .random(in: -170 ... -50),
                  spin: .random(in: -40...40))
        }
        Task {
            try? await Task.sleep(for: .milliseconds(30))
            withAnimation(.easeOut(duration: 1.3)) {
                for i in pieces.indices { pieces[i].flying = true }
            }
            try? await Task.sleep(for: .milliseconds(1400))
            pieces = []
        }
    }
}

#if DEBUG
/// `-BCTipJarPreview`: the Tip Jar with sample prices, for screenshots when the app isn't run from Xcode.
private struct PreviewTipStore: TipStore {
    func tips() async throws -> [Tip] {
        [Tip(id: "small", name: "Small Tip", price: "$0.99", sortPrice: 0.99),
         Tip(id: "medium", name: "Medium Tip", price: "$1.99", sortPrice: 1.99),
         Tip(id: "large", name: "Large Tip", price: "$2.99", sortPrice: 2.99)]
    }

    func buy(_ id: String) async throws -> TipOutcome { .thanked }

    /// `-BCTipJarSupporter` too: show the thank-you state.
    func hasTipped() async -> Bool { ProcessInfo.processInfo.arguments.contains("-BCTipJarSupporter") }
}
#endif
