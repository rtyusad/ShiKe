import Foundation
import SwiftData

/// 烹饪步骤实体
/// 每个 Recipe 包含多个 Step
@Model
final class Step {
    @Attribute(.unique) var id: UUID
    var stepNumber: Int
    var descriptionText: String
    var tipNote: String?
    /// 对应 B 站视频中的时间戳（秒）
    var videoTimestampSeconds: Int

    /// 所属食谱
    var recipe: Recipe?

    /// AC12: 级联删除关联的 StepImage
    @Relationship(deleteRule: .cascade, inverse: \StepImage.step)
    var images: [StepImage] = []

    init(
        id: UUID = UUID(),
        stepNumber: Int,
        descriptionText: String,
        tipNote: String? = nil,
        videoTimestampSeconds: Int
    ) {
        self.id = id
        self.stepNumber = stepNumber
        self.descriptionText = descriptionText
        self.tipNote = tipNote
        self.videoTimestampSeconds = videoTimestampSeconds
    }
}
