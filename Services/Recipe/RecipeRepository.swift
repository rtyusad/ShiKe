import Foundation
import SwiftData
import OSLog

/// 食谱保存参数（Sendable，安全跨 Actor 传递）
struct RecipeSaveData: Sendable {
    let title: String
    let bvNumber: String
    let sourceURL: String
    let sourceAuthor: String
    let cookTimeMinutes: Int?
    let difficultyLevel: Int

    struct StepData: Sendable {
        let stepNumber: Int
        let descriptionText: String
        let tipNote: String?
        let videoTimestampSeconds: Int
        let imagePath: String
        let thumbnailPath: String
        let orderIndex: Int
    }
    let steps: [StepData]
}

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

    /// 保存新食谱 + 消费免费槽位（同一事务，原子操作）
    /// ✅ 接收 Sendable 数据传输对象，不跨越 Actor 传递 @Model
    func saveAndConsumeSlot(with data: RecipeSaveData) throws {
        try ensureDefaultProfile()

        // 重复检查
        let bv = data.bvNumber
        var descriptor = FetchDescriptor<Recipe>(
            predicate: #Predicate { $0.bvNumber == bv && $0.isDeleted == false }
        )
        descriptor.fetchLimit = 1
        if try modelContext.fetch(descriptor).first != nil {
            throw AppError.duplicateRecipe(data.title)
        }

        // 消费免费槽位
        if let profile = try fetchProfile(), !profile.isPremium {
            guard profile.freeSlotsUsed < AppConstants.freeSlotLimit else {
                throw AppError.apiFailed(0, "免费槽位已用完，请升级以继续添加食谱")
            }
            profile.freeSlotsUsed += 1
        }

        // 在 Actor 内部创建 @Model 对象
        // 关键：必须先 insert 再操作 relationship，否则 SwiftData 运行时崩溃
        let recipe = Recipe(
            title: data.title,
            bvNumber: data.bvNumber,
            sourceURL: data.sourceURL,
            sourceAuthor: data.sourceAuthor,
            cookTimeMinutes: data.cookTimeMinutes,
            difficultyLevel: data.difficultyLevel
        )
        modelContext.insert(recipe)

        for stepData in data.steps {
            let step = Step(
                stepNumber: stepData.stepNumber,
                descriptionText: stepData.descriptionText,
                tipNote: stepData.tipNote,
                videoTimestampSeconds: stepData.videoTimestampSeconds
            )
            let stepImage = StepImage(
                imagePath: stepData.imagePath,
                thumbnailPath: stepData.thumbnailPath,
                timestampSeconds: stepData.videoTimestampSeconds,
                orderIndex: stepData.orderIndex
            )
            step.images = [stepImage]
            recipe.steps.append(step)
        }

        try modelContext.save()
        let used = (try? fetchProfile()?.freeSlotsUsed) ?? -1
        Logger.recipe.info("食谱已保存: \(data.title) (免费槽位: \(used))")
    }

    /// 保存新食谱（不消费槽位，供升级用户使用）
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
        let fileURLs = recipe.steps.flatMap { step in
            step.images.compactMap { image in
                [
                    URL(fileURLWithPath: image.imagePath),
                    URL(fileURLWithPath: image.thumbnailPath)
                ]
            }
        }.flatMap { $0 }

        recipe.isDeleted = true
        recipe.updatedAt = Date()
        try modelContext.save()

        let cleanup = FileCleanup()
        for url in fileURLs {
            cleanup.deleteFile(at: url)
        }

        if let profile = try fetchProfile(), !profile.isPremium {
            profile.freeSlotsUsed = max(0, profile.freeSlotsUsed - 1)
            try modelContext.save()
        }

        Logger.recipe.info("食谱已删除: \(recipe.title), 清理了 \(fileURLs.count) 个文件")
    }

    /// 永久删除（软删除 30 天后执行）
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

    /// 检查免费槽位
    func checkFreeSlot() throws -> Bool {
        guard let profile = try fetchProfile() else { return false }
        return profile.canCreateRecipe
    }

    /// 消耗一个免费槽位
    func consumeFreeSlot() throws {
        guard let profile = try fetchProfile(), !profile.isPremium else { return }
        guard profile.freeSlotsUsed < AppConstants.freeSlotLimit else {
            throw AppError.apiFailed(0, "免费槽位已用完")
        }
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