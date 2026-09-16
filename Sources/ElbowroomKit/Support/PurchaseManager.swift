import Foundation
import StoreKit
import Observation

/// The one-time Pro unlock through StoreKit 2. The entitlement is the
/// truth: `Transaction.currentEntitlements` unlocks on every launch and the
/// updates stream catches purchases from other devices. In a dev build with
/// no App Store product the paywall says so honestly instead of pretending.
@Observable
@MainActor
public final class PurchaseManager {
    public static let productID = "io.elbowroom.pro"

    public private(set) var product: Product?
    public private(set) var busy = false
    public var lastError: String?
    private var updatesTask: Task<Void, Never>?
    private let pro: ProStore

    public init(pro: ProStore) {
        self.pro = pro
    }

    /// True for any build that did not come through the App Store: no receipt
    /// on disk, or a sandbox (TestFlight / StoreKit-testing) receipt. Such
    /// builds may unlock Pro locally; a store build never shows that path.
    public nonisolated static var isDevDistribution: Bool {
        guard let url = Bundle.main.appStoreReceiptURL else { return true }
        if url.lastPathComponent == "sandboxReceipt" { return true }
        return !FileManager.default.fileExists(atPath: url.path)
    }

    public func start() {
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
        Task {
            await refreshEntitlements()
            product = try? await Product.products(for: [Self.productID]).first
        }
    }

    /// Localized store price when the product loaded, else the deck's line.
    public var priceLine: String {
        if let product {
            return Loc.lang == "ja"
                ? "\(product.displayPrice) の買い切り。サブスクリプションはありません。"
                : "\(product.displayPrice), one time. No subscription."
        }
        return Copy.paywallPrice
    }

    public var storeReachable: Bool { product != nil }

    public func refreshEntitlements() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                pro.unlock()
            }
        }
    }

    public func purchase() async -> Bool {
        guard let product else { return false }
        busy = true
        defer { busy = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else { return false }
                pro.unlock()
                await transaction.finish()
                return true
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    public func restore() async {
        busy = true
        defer { busy = false }
        try? await AppStore.sync()
        await refreshEntitlements()
    }

    private func handle(_ result: VerificationResult<StoreKit.Transaction>) async {
        guard case .verified(let transaction) = result,
              transaction.productID == Self.productID else { return }
        if transaction.revocationDate == nil {
            pro.unlock()
        }
        await transaction.finish()
    }
}
