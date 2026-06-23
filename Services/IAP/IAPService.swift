import Foundation
import StoreKit
import OSLog
/// 内购服务（StoreKit 2）
/// 处理 ¥8 终身买断 (Non-Consumable IAP) + 恢复购买
@Observable
final class IAPService {
    private(set) var isPurchasing = false
    private(set) var purchaseError: Error?

    /// 终身买断产品
    private var lifetimeProduct: Product?

    // MARK: - 初始化

    init() {
        Task {
            await loadProducts()
            await listenForTransactions()
        }
    }

    // MARK: - 加载产品

    func loadProducts() async {
        do {
            let products = try await Product.products(for: [AppConstants.lifetimeProductID])
            lifetimeProduct = products.first
            Logger.iap.info("IAP 产品加载成功: \(products.map(\.displayName))")
        } catch {
            Logger.iap.error("IAP 产品加载失败: \(error)")
            purchaseError = error
        }
    }

    // MARK: - 购买

    /// 执行终身买断购买
    func purchaseLifetime() async throws -> Bool {
        guard let product = lifetimeProduct else {
            await loadProducts()
            guard let product = lifetimeProduct else {
                throw AppError.apiFailed(0, "无法加载商品信息")
            }
            return false
        }

        isPurchasing = true
        defer { isPurchasing = false }

        Logger.iap.info("开始购买: \(product.displayName) ¥\(product.displayPrice)")
        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            // 验证交易
            let transaction = try checkVerified(verification)
            Logger.iap.info("购买成功: \(transaction.productID)")

            // 标记付费状态
            try? await AppContainer.shared.recipeRepo.setPremium(true)

            await transaction.finish()
            return true

        case .userCancelled:
            Logger.iap.info("用户取消购买")
            return false

        case .pending:
            Logger.iap.info("购买等待中...")
            return false

        @unknown default:
            return false
        }
    }

    // MARK: - 恢复购买

    /// 恢复已购买的终身买断
    func restorePurchases() async throws -> Bool {
        Logger.iap.info("恢复购买...")
        var restored = false

        for await verification in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(verification),
               transaction.productID == AppConstants.lifetimeProductID {
                restored = true
                await transaction.finish()
            }
        }

        if restored {
            try? await AppContainer.shared.recipeRepo.setPremium(true)
            Logger.iap.info("恢复购买成功")
        }

        return restored
    }

    // MARK: - 交易监听

    /// 监听 StoreKit 2 交易更新（后台推送等）
    private func listenForTransactions() async {
        for await verification in Transaction.updates {
            guard let transaction = try? checkVerified(verification),
                  transaction.productID == AppConstants.lifetimeProductID
            else { continue }

            try? await AppContainer.shared.recipeRepo.setPremium(true)
            await transaction.finish()
            Logger.iap.info("交易更新处理完成: \(transaction.productID)")
        }
    }

    // MARK: - 验证

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw AppError.apiFailed(0, "交易验证失败")
        case .verified(let safe):
            return safe
        }
    }
}
