import SwiftUI
import Observation

/// 食谱详情（步骤卡片浏览）ViewModel
@MainActor
@Observable
final class RecipeDetailViewModel {
    private let repo: RecipeRepository
    private let imageCache: ImageCache

    let recipe: Recipe

    private(set) var currentStepIndex: Int = 0
    private(set) var isLoadingImage = false

    var steps: [Step] {
        recipe.steps.sorted { $0.stepNumber < $1.stepNumber }
    }

    var currentStep: Step? {
        guard currentStepIndex < steps.count else { return nil }
        return steps[currentStepIndex]
    }

    var totalSteps: Int { steps.count }
    var isFirstStep: Bool { currentStepIndex == 0 }
    var isLastStep: Bool { currentStepIndex >= steps.count - 1 }

    init(recipe: Recipe, repo: RecipeRepository, imageCache: ImageCache) {
        self.recipe = recipe
        self.repo = repo
        self.imageCache = imageCache
    }

    // MARK: - 输入

    func goToNextStep() {
        guard currentStepIndex < steps.count - 1 else { return }
        currentStepIndex += 1
    }

    func goToPreviousStep() {
        guard currentStepIndex > 0 else { return }
        currentStepIndex -= 1
    }

    func goToStep(_ index: Int) {
        guard index >= 0, index < steps.count else { return }
        currentStepIndex = index
    }

    func imageForCurrentStep() -> UIImage? {
        guard let step = currentStep,
              let image = step.images.first else { return nil }

        // 1. ImageCache
        if let cached = imageCache.image(forKey: image.imagePath) {
            return cached
        }

        // 2. 降级：磁盘直接加载 + 回填缓存
        let url = URL(fileURLWithPath: image.imagePath)
        if let data = try? Data(contentsOf: url),
           let uiImage = UIImage(data: data) {
            imageCache.setImage(uiImage, forKey: image.imagePath)
            return uiImage
        }
        return nil
    }

    func deleteRecipe() async throws {
        try await repo.softDelete(recipe)
    }
}
