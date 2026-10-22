import SwiftUI

/// Layout for the server and sign-in screens. A grouped form on iPhone and iPad; on the Mac a
/// centred column, because a Mac form draws a box behind every section, even the header.
struct OnboardingForm<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        #if os(macOS)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                content
            }
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 400)
            .padding(.horizontal, 32)
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity)
        }
        #else
        Form { content }
            .formStyle(.grouped)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        #endif
    }
}
