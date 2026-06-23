import SwiftUI
import SwiftData
import OSLog
/// 食刻 App 主入口
/// 启动时执行孤儿临时文件清理、注册网络监控
@main
struct ShiKeApp: App {
    private let container = AppContainer.shared

    init() {
        // AC13: 启动时清理上次运行残留的临时 mp4
        FileCleanup().cleanupOrphanedFiles()
        Logger.lifecycle.info("食刻 App 启动，已完成孤儿文件清理")
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(\.appContainer, container)
                .onAppear {
                    // 首次启动引导：创建默认 UserProfile
                    Task {
                        try? await container.recipeRepo.ensureDefaultProfile()
                    }
                }
        }
        .modelContainer(container.modelContainer)
    }
}

