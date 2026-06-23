import Foundation
import SwiftData

/// 用户档案（单例实体，App 只创建一条记录）
/// 存储用户偏好、付费状态、免费额度使用情况
@Model
final class UserProfile {
    @Attribute(.unique) var id: UUID
    var nickname: String
    var avatarPath: String?
    var freeSlotsUsed: Int
    var isPremium: Bool
    var totalCookCount: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        nickname: String = "",
        avatarPath: String? = nil,
        freeSlotsUsed: Int = 0,
        isPremium: Bool = false,
        totalCookCount: Int = 0
    ) {
        self.id = id
        self.nickname = nickname
        self.avatarPath = avatarPath
        self.freeSlotsUsed = freeSlotsUsed
        self.isPremium = isPremium
        self.totalCookCount = totalCookCount
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// 当前可用免费槽位
    var remainingFreeSlots: Int {
        max(0, AppConstants.freeSlotLimit - freeSlotsUsed)
    }

    /// 是否可以新建食谱（付费用户无限，免费用户受额度限制）
    var canCreateRecipe: Bool {
        isPremium || freeSlotsUsed < AppConstants.freeSlotLimit
    }
}
