import SwiftUI
import Observation

/// 付费升级 ViewModel
@MainActor
@Observable
final class UpgradeViewModel {
    private let iapService: IAPService

    private(set) var isPurchasing = false
    private(set) var purchaseSuccess = false
    private(set) var error: AppError?

    init(iapService: IAPService) {
        self.iapService = iapService
    }

    // MARK: - 输入

    func purchase() async {
        isPurchasing = true
        error = nil

        do {
            purchaseSuccess = try await iapService.purchaseLifetime()
        } catch let appError as AppError {
            error = appError
        } catch {
            error = .apiFailed(0, error.localizedDescription)
        }

        isPurchasing = false
    }

    func restorePurchases() async {
        isPurchasing = true
        error = nil

        do {
            purchaseSuccess = try await iapService.restorePurchases()
            if !purchaseSuccess {
                error = .apiFailed(0, "未找到已购买记录")
            }
        } catch let appError as AppError {
            error = appError
        } catch {
            error = .apiFailed(0, error.localizedDescription)
        }

        isPurchasing = false
    }
}
