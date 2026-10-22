import ByteCacheCore
import ByteCacheLanguage
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
    public let settings: AppSettings
    public let cloudSync: CloudSyncCoordinator
    public let lock: AppLockModel
    public let widgets: WidgetSnapshotWriter
    /// Uploads snippets saved while offline.
    public let saveQueue: SaveQueueFlusher
    /// New releases on GitHub, and What's New after an update.
    public let updates: UpdateModel
    /// Quick Search (Mac menu bar and global shortcut) has its own list, so it doesn't disturb the window's.
    public let quickSearch: QuickSearchModel

    public init(
        store: any CredentialStore = AppEnvironment.makeCredentialStore(),
        transport: any HTTPTransport = URLSession.shared,
        cache: SnippetCache? = try? SnippetCache(),
        detector: LanguageDetector = LanguageDetector(),
        settings: AppSettings = AppSettings(),
        cloud: (any KeyValueSyncStore)? = nil,
        lock: AppLockModel = AppLockModel(),
        pendingSaves: PendingSaveQueue = .shared
    ) {
        session = SessionManager(store: store, transport: transport)
        onboarding = OnboardingModel(session: session)
        self.cache = cache
        self.detector = detector
        self.settings = settings
        self.lock = lock
        widgets = WidgetSnapshotWriter(session: session, smartGroups: { [settings] in settings.smartGroups })
        quickSearch = QuickSearchModel(list: SnippetListModel(session: session, cache: cache))
        saveQueue = SaveQueueFlusher(session: session, queue: pendingSaves)
        updates = UpdateModel(checker: Self.makeUpdateChecker())
        lock.appDidLaunch()
        cloudSync = CloudSyncCoordinator(settings: settings, session: session, cloud: cloud ?? UbiquitousSyncStore())
    }
}

extension AppServices {
    /// Debug builds: env BC_DEBUG_PRETEND_VERSION (e.g. 1.0.0) makes What's New think the app was updated to that version.
    static func makeUpdateChecker() -> UpdateChecker {
        #if DEBUG
        if let pretend = ProcessInfo.processInfo.environment["BC_DEBUG_PRETEND_VERSION"].flatMap(AppVersion.init) {
            // A fresh record each launch, so the once-a-day limit never hides the sheet while testing.
            return UpdateChecker(current: pretend, defaults: UserDefaults(suiteName: "bytecache.debug.updates.\(UUID().uuidString)") ?? .standard)
        }
        #endif
        return UpdateChecker()
    }
}
