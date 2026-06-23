import Foundation
import SwiftData

/// 步骤截图实体
/// 存储高清截图和缩略图的文件路径
/// 关联文件系统中的 HEIC 文件
@Model
final class StepImage {
    @Attribute(.unique) var id: UUID
    /// HEIC 高清截图文件路径
    var imagePath: String
    /// 缩略图文件路径（300px，用于列表卡片）
    var thumbnailPath: String
    /// 对应视频时间戳（秒）
    var timestampSeconds: Int
    /// 排序序号
    var orderIndex: Int

    /// 所属步骤
    var step: Step?

    init(
        id: UUID = UUID(),
        imagePath: String,
        thumbnailPath: String,
        timestampSeconds: Int,
        orderIndex: Int
    ) {
        self.id = id
        self.imagePath = imagePath
        self.thumbnailPath = thumbnailPath
        self.timestampSeconds = timestampSeconds
        self.orderIndex = orderIndex
    }

    /// 本地文件 URL（用于文件系统操作）
    var localFileURL: URL? {
        URL(string: imagePath)
    }
}
