import Foundation
import Observation
import StoreKit

/// One tip as the Tip Jar shows it. Prices come from the App Store, in the person's currency.
public struct Tip: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let price: String
    public let sortPrice: Decimal

    public init(id: String, name: String, price: String, sortPrice: Decimal) {
        self.id = id
        self.name = name
        self.price = price
        self.sortPrice = sortPrice
    }
}

public enum TipOutcome: Sendable {
    case thanked, cancelled
    /// Waiting on Ask to Buy or a payment check; it finishes later through `Transaction.updates`.
    case pending
}

/// Where tips come from and go to: the App Store, or a fake in tests.
public protocol TipStore: Sendable {
    func tips() async throws -> [Tip]
    func buy(_ id: String) async throws -> TipOutcome
    /// Whether this Apple Account has ever tipped (on any device, and after reinstalling).
    func hasTipped() async -> Bool
}

/// The Tip Jar's products (CP-96): consumables, so people can tip more than once. They unlock nothing.
public enum TipJar {
    public static let productIDs = [
        "me.suryajs.bytecache.tip.small",
        "me.suryajs.bytecache.tip.medium",
        "me.suryajs.bytecache.tip.large",
    ]

    /// Finishes tips that complete outside the app (Ask to Buy, delayed payments). Call once at launch.
    public static func finishTipsInBackground() {
        Task.detached {
            for await update in Transaction.updates {
                if case .verified(let transaction) = update { await transaction.finish() }
            }
        }
    }
}

/// The real store: StoreKit 2.
public struct AppStoreTipStore: TipStore {
    public init() {}

    public func tips() async throws -> [Tip] {
        try await Product.products(for: TipJar.productIDs).map {
            Tip(id: $0.id, name: $0.displayName, price: $0.displayPrice, sortPrice: $0.price)
        }
    }

    public func buy(_ id: String) async throws -> TipOutcome {
        guard let product = try await Product.products(for: [id]).first else { throw TipJarError.unavailable }
        switch try await product.purchase() {
        case .success(.verified(let transaction)):
            await transaction.finish()
            return .thanked
        case .success(.unverified):
            throw TipJarError.unverified
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    /// Consumables show up in `Transaction.all` because Info.plist sets
    /// `SKIncludeConsumableInAppPurchaseHistory` (iOS 18 / macOS 15). Refunded tips don't count.
    public func hasTipped() async -> Bool {
        for await result in Transaction.all {
            if case .verified(let transaction) = result, TipJar.productIDs.contains(transaction.productID),
               transaction.revocationDate == nil {
                return true
            }
        }
        return false
    }
}

public enum TipJarError: LocalizedError {
    case unavailable, unverified

    public var errorDescription: String? {
        switch self {
        case .unavailable: "Tips aren't available right now. Try again later."
        case .unverified: "The App Store couldn't confirm this tip. Please try again."
        }
    }
}

@MainActor @Observable
public final class TipJarModel {
    public enum State: Equatable {
        case loading, ready, unavailable
    }

    public private(set) var state = State.loading
    public private(set) var tips: [Tip] = []
    /// The tip being bought; its button shows progress and the others wait.
    public private(set) var buying: String?
    /// Has tipped before: About shows a Supporter badge and a thank-you instead of the ask.
    public private(set) var isSupporter = false
    /// Goes up with each tip, so the Tip Jar can play its burst.
    public private(set) var celebrations = 0
    public var showsPending = false
    public var errorMessage: String?

    @ObservationIgnored private let store: TipStore

    public init(store: TipStore = AppStoreTipStore()) {
        self.store = store
    }

    public func load() async {
        if !isSupporter { isSupporter = await store.hasTipped() }
        guard tips.isEmpty else { return }
        state = .loading
        do {
            tips = try await store.tips().sorted { $0.sortPrice < $1.sortPrice }
            state = tips.isEmpty ? .unavailable : .ready
        } catch {
            state = .unavailable
        }
    }

    public func buy(_ tip: Tip) async {
        guard buying == nil else { return }
        buying = tip.id
        defer { buying = nil }
        do {
            switch try await store.buy(tip.id) {
            case .thanked:
                isSupporter = true
                celebrations += 1
                Haptics.play(.success)
            case .pending: showsPending = true
            case .cancelled: break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
