import SwiftUI
import SwiftData
import Observation
import OSLog
/// 食谱库首页 ViewModel
@MainActor
@Observable
final class LibraryViewModel {
    private let repo: RecipeRepository
    private let imageCache: ImageCache

    private(set) var recipes: [Recipe] = []
    private(set) var isLoading = false
    private(set) var error: AppError?
    private(set) var freeSlotsRemaining: Int = AppConstants.freeSlotLimit
    private(set) var isPremium: Bool = false

    // MARK: - 初始化

    init(repo: RecipeRepository, imageCache: ImageCache) {
        self.repo = repo
        self.imageCache = imageCache
    }

    // MARK: - 输入

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            recipes = try await repo.fetchAll()
            if let profile = try await repo.fetchProfile() {
                freeSlotsRemaining = profile.remainingFreeSlots
                isPremium = profile.isPremium
            }
            error = nil
        } catch {
            self.error = error as? AppError ?? .apiFailed(0, error.localizedDescription)
            Logger.recipe.error("食谱加载失败: \(error)")
        }
    }

    func deleteRecipe(_ recipe: Recipe) async {
        do {
            try await repo.softDelete(recipe)
            recipes.removeAll { $0.id == recipe.id }
            await load()  // 刷新免费额度
        } catch {
            self.error = error as? AppError ?? .apiFailed(0, error.localizedDescription)
        }
    }

    func thumbnailFor(_ recipe: Recipe) -> UIImage? {
        guard let firstStep = recipe.steps.first,
              let firstImage = firstStep.images.first else {
            return nil
        }
        return imageCache.image(forKey: firstImage.thumbnailPath)
    }
}
