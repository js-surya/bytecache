import SwiftUI

/// The Tip Jar in About: one row per tip with its App Store price. Hidden when the store has no tips
/// (for example before the products are approved), so About never shows a broken section.
struct TipJarSection: View {
    @State private var model: TipJarModel

    init(model: TipJarModel = TipJarModel()) {
        _model = State(initialValue: model)
    }

    var body: some View {
        Group {
            if model.state == .ready {
                Section {
                    ForEach(model.tips) { tip in
                        TipRow(tip: tip, buying: model.buying == tip.id, disabled: model.buying != nil) {
                            Task { await model.buy(tip) }
                        }
                    }
                } header: {
                    Text("Tip Jar")
                } footer: {
                    InfoFooter("ByteCache is free and open source. Tips are optional, unlock nothing and help keep it going.")
                }
            }
        }
        .task { await model.load() }
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

private struct TipRow: View {
    let tip: Tip
    let buying: Bool
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(.tipJar, color: .orange)
            Text(tip.name)
            Spacer(minLength: 8)
            if buying {
                ProgressView().controlSize(.small)
            } else {
                Button(tip.price, action: action)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .disabled(disabled)
                    .touchTarget()
                    .accessibilityLabel("\(tip.name), \(tip.price)")
            }
        }
    }
}
