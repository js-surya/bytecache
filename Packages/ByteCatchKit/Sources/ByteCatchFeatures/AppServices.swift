import ByteCatchCore
import ByteCatchLanguage
import Foundation
import Observation

/// The long-lived objects the app shares between scenes.
@MainActor @Observable
public final class AppServices {
    public let session: SessionManager
    public let onboarding: OnboardingModel
    /// Nil only if the on-disk store can't be opened; the app then works online-only.
    public let cache: SnippetCache?
    public let detector: LanguageDetector

    public init(
        store: any CredentialStore = AppEnvironment.makeCredentialStore(),
        transport: any HTTPTransport = URLSession.shared,
        cache: SnippetCache? = try? SnippetCache(),
        detector: LanguageDetector = LanguageDetector()
    ) {
        session = SessionManager(store: store, transport: transport)
        onboarding = OnboardingModel(session: session)
        self.cache = cache
        self.detector = detector
    }
}
