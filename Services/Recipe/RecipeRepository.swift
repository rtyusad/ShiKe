import Foundation
import SwiftData
import OSLog
/// 食谱数据仓库
/// 封装 SwiftData CRUD 操作 + 级联文件清理
@ModelActor
actor RecipeRepository {
    /// 确保默认 UserProfile 存在（首次启动）
    func ensureDefaultProfile() throws {
        let descriptor = FetchDescriptor<UserProfile>()
        let count = try modelContext.fetchCount(descriptor)
        if count == 0 {
            let profile = UserProfile()
            modelContext.insert(profile)
            try modelContext.save()
            Logger.recipe.info("默认 UserProfile 已创建")
        }
    }

    // MARK: - 查询

    /// 获取所有未删除的食谱（按更新时间倒序）
    func fetchAll() throws -> [Recipe] {
        var descriptor = FetchDescriptor<Recipe>(
            predicate: #Predicate { $0.isDeleted == false },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.relationshipKeyPathsForPrefetching = []
        return try modelContext.fetch(descriptor)
    }

    /// 按 BV 号查找食谱
    func findByBV(_ bvNumber: String) throws -> Recipe? {
        let bv = bvNumber
        var descriptor = FetchDescriptor<Recipe>(
            predicate: #Predicate { $0.bvNumber == bv && $0.isDeleted == false }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// 获取 UserProfile
    func fetchProfile() throws -> UserProfile? {
        var descriptor = FetchDescriptor<UserProfile>()
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    // MARK: - 写入

    /// 保存新食谱
    func save(_ recipe: Recipe) throws {
        modelContext.insert(recipe)
        try modelContext.save()
        Logger.recipe.info("食谱已保存: \(recipe.title)")
    }

    /// 更新食谱
    func update(_ recipe: Recipe) throws {
        recipe.updatedAt = Date()
        try modelContext.save()
    }

    // MARK: - 删除（含级联文件清理 — AC12）

    /// 软删除食谱 + 级联清理关联文件
    func softDelete(_ recipe: Recipe) throws {
        // 1. 收集所有关联文件路径（在标记删除之前）
        let fileURLs = recipe.steps.flatMap { step in
            step.images.compactMap { image in
                [
                    URL(fileURLWithPath: image.imagePath),
                    URL(fileURLWithPath: image.thumbnailPath)
                ]
            }
        }.flatMap { $0 }

        // 2. 标记软删除
        recipe.isDeleted = true
        recipe.updatedAt = Date()
        try modelContext.save()

        // 3. 异步清理文件系统（失败不阻塞，仅记日志）
        let cleanup = FileCleanup()
        for url in fileURLs {
            cleanup.deleteFile(at: url)
        }

        // 4. 释放免费额度（如用户未付费）
        if let profile = try fetchProfile(), !profile.isPremium {
            profile.freeSlotsUsed = max(0, profile.freeSlotsUsed - 1)
            try modelContext.save()
        }

        Logger.recipe.info("食谱已删除: \(recipe.title), 清理了 \(fileURLs.count) 个文件")
    }

    /// 永久删除（软删除 30 天后执行，由后台清理逻辑触发）
    func hardDelete(_ recipe: Recipe) throws {
        modelContext.delete(recipe)
        try modelContext.save()
    }

    // MARK: - 用户信息

    /// 更新用户昵称
    func updateNickname(_ name: String) throws {
        guard let profile = try fetchProfile() else { return }
        profile.nickname = name
        profile.updatedAt = Date()
        try modelContext.save()
    }

    /// 检查并消耗免费额度
    func checkFreeSlot() throws -> Bool {
        guard let profile = try fetchProfile() else { return false }
        return profile.canCreateRecipe
    }

    /// 消耗一个免费槽位
    func consumeFreeSlot() throws {
        guard let profile = try fetchProfile(), !profile.isPremium else { return }
        profile.freeSlotsUsed += 1
        try modelContext.save()
    }

    /// 标记付费状态
    func setPremium(_ isPremium: Bool) throws {
        guard let profile = try fetchProfile() else { return }
        profile.isPremium = isPremium
        profile.updatedAt = Date()
        try modelContext.save()
    }

    /// 增加跟做完成计数
    func incrementCookCount() throws {
        guard let profile = try fetchProfile() else { return }
        profile.totalCookCount += 1
        try modelContext.save()
    }
}
