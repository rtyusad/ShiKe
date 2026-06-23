import Foundation
import SwiftData

/// 食谱实体
/// 从 B 站视频转化而来的完整食谱数据
@Model
final class Recipe {
    @Attribute(.unique) var id: UUID
    var title: String
    var bvNumber: String
    var sourceURL: String
    /// UP 主名称（不可编辑/不可删除 — AC07）
    var sourceAuthor: String
    var cookTimeMinutes: Int?
    var difficultyLevel: Int          // 1=简单, 2=中等, 3=困难
    var isDeleted: Bool
    var createdAt: Date
    var updatedAt: Date

    /// AC12: 级联删除关联的 Step
    @Relationship(deleteRule: .cascade, inverse: \Step.recipe)
    var steps: [Step] = []

    init(
        id: UUID = UUID(),
        title: String,
        bvNumber: String,
        sourceURL: String,
        sourceAuthor: String,
        cookTimeMinutes: Int? = nil,
        difficultyLevel: Int = 2
    ) {
        self.id = id
        self.title = title
        self.bvNumber = bvNumber
        self.sourceURL = sourceURL
        self.sourceAuthor = sourceAuthor
        self.cookTimeMinutes = cookTimeMinutes
        self.difficultyLevel = difficultyLevel
        self.isDeleted = false
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
