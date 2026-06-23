import SwiftUI
import Observation
import OSLog
/// 个人中心 ViewModel
@MainActor
@Observable
final class ProfileViewModel {
    private let repo: RecipeRepository
    private let iapService: IAPService

    private(set) var nickname: String = ""
    private(set) var avatarPath: String?
    private(set) var freeSlotsUsed: Int = 0
    private(set) var freeSlotsLimit: Int = AppConstants.freeSlotLimit
    private(set) var isPremium: Bool = false
    private(set) var totalCookCount: Int = 0
    private(set) var totalRecipes: Int = 0
    private(set) var isLoading = false

    init(repo: RecipeRepository, iapService: IAPService) {
        self.repo = repo
        self.iapService = iapService
    }

    // MARK: - 输入

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            if let profile = try await repo.fetchProfile() {
                nickname = profile.nickname
                freeSlotsUsed = profile.freeSlotsUsed
                isPremium = profile.isPremium
                totalCookCount = profile.totalCookCount
            }
            let recipes = try await repo.fetchAll()
            totalRecipes = recipes.count
        } catch {
            Logger.recipe.error("个人中心加载失败: \(error)")
        }
    }

    func updateNickname(_ name: String) async {
        guard name.count >= AppConstants.nicknameMinLength,
              name.count <= AppConstants.nicknameMaxLength else { return }

        do {
            try await repo.updateNickname(name)
            nickname = name
        } catch {
            Logger.recipe.error("昵称更新失败: \(error)")
        }
    }
}
