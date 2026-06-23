import SwiftUI
import SwiftData
import OSLog

/// 自定义环境键：注入 AppContainer
struct AppContainerKey: EnvironmentKey {
    static let defaultValue: AppContainer = .shared
}

extension EnvironmentValues {
    var appContainer: AppContainer {
        get { self[AppContainerKey.self] }
        set { self[AppContainerKey.self] = newValue }
    }
}

/// 轻量 DI 容器，零三方依赖
///
/// 设计原则：
/// - Service 工厂方法不绑 @MainActor（VLMService、FrameExtractionActor 是独立 actor）
/// - ViewModel 工厂方法绑 @MainActor（持有 @Observable 状态）
/// - 长生命周期 Service 保持单例引用
final class AppContainer {
    static let shared = AppContainer()

    // MARK: - SwiftData

    let modelContainer: ModelContainer

    // MARK: - 长生命周期 Service

    let biliAPI: BiliAPIService
    let recipeRepo: RecipeRepository
    let iapService: IAPService
    let imageCache: ImageCache
    let networkMonitor: NetworkMonitor
    let fileCleanup: FileCleanup

    // MARK: - Service 工厂（不绑 @MainActor）

    func makeFrameExtractionActor() -> FrameExtractionActor {
        FrameExtractionActor(
            playURLAPI: BiliPlayURLAPI(signer: WbiSigner()),
            downloader: GOPDownloader(),
            sidxParser: SidxBoxParser(),
            assembler: MP4Assembler(),
            extractor: IFrameExtractor(),
            cleanup: fileCleanup
        )
    }

    func makeVLMService() -> VLMService {
        VLMService()
    }

    // MARK: - ViewModel 工厂（@MainActor）

    @MainActor
    func makeLibraryVM() -> LibraryViewModel {
        LibraryViewModel(repo: recipeRepo, imageCache: imageCache)
    }

    @MainActor
    func makeAddRecipeVM() -> AddRecipeViewModel {
        AddRecipeViewModel(
            biliAPI: biliAPI,
            frameExtractionActor: makeFrameExtractionActor(),
            vlmService: makeVLMService(),
            recipeRepo: recipeRepo,
            networkMonitor: networkMonitor
        )
    }

    @MainActor
    func makeRecipeDetailVM(recipe: Recipe) -> RecipeDetailViewModel {
        RecipeDetailViewModel(recipe: recipe, repo: recipeRepo, imageCache: imageCache)
    }

    @MainActor
    func makeCookingVM(recipe: Recipe) -> CookingViewModel {
        CookingViewModel(recipe: recipe)
    }

    @MainActor
    func makeProfileVM() -> ProfileViewModel {
        ProfileViewModel(repo: recipeRepo, iapService: iapService)
    }

    @MainActor
    func makeUpgradeVM() -> UpgradeViewModel {
        UpgradeViewModel(iapService: iapService)
    }

    // MARK: - 初始化

    private init() {
        do {
            self.modelContainer = try ModelContainer(
                for: Recipe.self, Step.self, StepImage.self, UserProfile.self
            )
        } catch {
            fatalError("SwiftData ModelContainer 初始化失败: \(error)")
        }

        self.recipeRepo = RecipeRepository(modelContainer: modelContainer)
        self.biliAPI = BiliAPIService()
        self.iapService = IAPService()
        self.imageCache = ImageCache()
        self.networkMonitor = NetworkMonitor.shared
        self.fileCleanup = FileCleanup()

        Logger.lifecycle.info("AppContainer 初始化完成")
    }
}
