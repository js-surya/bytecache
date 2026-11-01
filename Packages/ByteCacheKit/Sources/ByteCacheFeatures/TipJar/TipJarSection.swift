import SwiftUI

/// The Tip Jar in About: one row per tip with its App Store price. Hidden when the store has no tips
/// (for example before the products are approved), so About never shows a broken section. About
/// loads the model: a view that starts out empty never runs its own `.task`.
struct TipJarSection: View {
    @Bindable var model: TipJarModel

    var body: some View {
        if model.state == .ready {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        SettingsIcon(.tipJar, color: .orange)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Tip Jar")
                            Text("Enjoying ByteCache? Buy me a coffee.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 10) {
                        ForEach(Array(model.tips.enumerated()), id: \.element.id) { index, tip in
                            TipButton(tip: tip, cups: index + 1, buying: model.buying == tip.id,
                                      disabled: model.buying != nil) {
                                Task { await model.buy(tip) }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            } footer: {
                InfoFooter("ByteCache is free and open source. Tips are optional, unlock nothing and help keep it going.")
            }
            .alert("Thank You!", isPresented: $model.showsThanks) {
                Button("OK") {}
            } message: {
                Text("Your tip means a lot and helps keep ByteCache going.")
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

/// One tip: more cups for a bigger tip, and the price underneath.
private struct TipButton: View {
    let tip: Tip
    let cups: Int
    let buying: Bool
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                HStack(spacing: 1) {
                    ForEach(0..<cups, id: \.self) { _ in Icon(.tipJar) }
                }
                .font(.footnote)
                .foregroundStyle(.orange)
                .frame(height: 18)
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

#if DEBUG
/// `-BCTipJarPreview`: the Tip Jar with sample prices, for screenshots when the app isn't run from Xcode.
private struct PreviewTipStore: TipStore {
    func tips() async throws -> [Tip] {
        [Tip(id: "small", name: "Small Tip", price: "$0.99", sortPrice: 0.99),
         Tip(id: "medium", name: "Medium Tip", price: "$1.99", sortPrice: 1.99),
         Tip(id: "large", name: "Large Tip", price: "$2.99", sortPrice: 2.99)]
    }

    func buy(_ id: String) async throws -> TipOutcome { .thanked }
}
#endif
