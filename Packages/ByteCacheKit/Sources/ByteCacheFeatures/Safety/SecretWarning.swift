import SwiftUI

/// Orange banner shown when code looks like it contains credentials. Saving is still allowed.
struct SecretWarning: View {
    @Binding var text: String
    @State private var dismissedFor: String?

    var body: some View {
        let findings = SecretScanner.scan(text)
        if !findings.isEmpty, dismissedFor != text {
            VStack(alignment: .leading, spacing: 8) {
                Label("This looks like it contains secrets", symbol: .warning)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                Text(findings.prefix(4).map { "\($0.kind.title) (line \($0.line))" }.joined(separator: " · ")
                     + (findings.count > 4 ? " · …" : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Replace with \(SecretScanner.placeholder)") { text = SecretScanner.redact(text) }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    Button("Keep") { dismissedFor = text }
                        .buttonStyle(.bordered)
                }
                .controlSize(.small)
                .touchTarget()
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .contain)
        }
    }
}
