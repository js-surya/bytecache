import SwiftUI

/// Covers a window while the app is locked (and hides it in the app switcher).
struct AppLockCover: ViewModifier {
    let lock: AppLockModel
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .overlay {
                if lock.isLocked {
                    LockScreenView(lock: lock).transition(.opacity)
                } else if lock.isEnabled && scenePhase != .active && isPhone {
                    PrivacyCover().transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: lock.isLocked)
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active: lock.didReturnToApp()
                default: lock.didLeaveApp()
                }
            }
    }

    private var isPhone: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }
}

extension View {
    public func appLockCover(_ lock: AppLockModel) -> some View { modifier(AppLockCover(lock: lock)) }
}

private struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.background)
            Image(systemName: "curlybraces.square.fill").font(.system(size: 64)).foregroundStyle(.tint)
        }
        .ignoresSafeArea()
    }
}

struct LockScreenView: View {
    let lock: AppLockModel

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 76, height: 76)
                .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Text("ByteCatch is Locked").font(.title2.bold())
            Button {
                Task { await lock.unlock() }
            } label: {
                Label("Unlock with \(lock.biometry.name)", systemImage: lock.biometry.systemImage)
                    .font(.headline)
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .ignoresSafeArea()
        .task { await lock.unlock() }
    }
}

struct AppLockSettingsView: View {
    let lock: AppLockModel
    @State private var message: String?

    var body: some View {
        @Bindable var lock = lock
        List {
            Section {
                Toggle(isOn: Binding(get: { lock.isEnabled }, set: { on in
                    Task {
                        message = nil
                        if !(await lock.setEnabled(on)) {
                            message = lock.canAuthenticate
                                ? "\(lock.biometry.name) didn't confirm it's you, so nothing changed."
                                : "Set up \(lock.biometry == .none ? "a passcode" : lock.biometry.name) on this device first."
                        }
                    }
                })) {
                    Text("Require \(lock.biometry.name)")
                }
                if lock.isEnabled {
                    Picker("Ask Again", selection: $lock.timeout) {
                        ForEach(LockTimeout.allCases) { Text($0.title).tag($0) }
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if let message { Text(message).foregroundStyle(.red) }
                    Text("ByteCatch asks for \(lock.biometry.name) (or your passcode) when it opens and when you come back after the chosen time. While locked, widgets hide your snippets. Saving from the share sheet and Shortcuts still works, so capturing stays one step.")
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle("App Lock")
    }
}
