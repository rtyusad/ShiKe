import UIKit
import Foundation

/// B 站视频雪碧图 API (零签名)
/// GET /x/player/videoshot?bvid={BV号}&index=1
///
/// 返回：
/// - 雪碧图 JPG 图片 URL（10 列 × N 行，每格尺寸 = 图宽÷10 × 图高÷行数）
/// - JSON 时间戳数组（index=1）
///
/// 实测：1600×900px (16:9视频) → 33帧 → 10×4 网格 → 160×225px/格
struct BiliVideoShotAPI {
    private let api: BiliAPIService

    init(api: BiliAPIService = BiliAPIService()) {
        self.api = api
    }

    struct VideoShotResult {
        /// 雪碧图 UIImage
        let spriteImage: UIImage
        /// 时间戳数组（秒），对应雪碧图中每个格子的视频时间
        let timestamps: [Int]
        /// 网格列数（B站固定 10 列）
        let columns: Int
        /// 格子宽度（px）= 图宽 / columns
        let cellWidth: Int
        /// 格子高度（px）= 图高 / rows
        let cellHeight: Int
        /// 网格行数
        var rows: Int {
            guard columns > 0 else { return 1 }
            return max(1, (timestamps.count + columns - 1) / columns)
        }

        init(spriteImage: UIImage, timestamps: [Int]) {
            self.spriteImage = spriteImage
            self.timestamps = timestamps
            self.columns = 10  // B站固定 10 列

            // 从图像实际尺寸动态计算格子大小
            let imgWidth = Int(spriteImage.size.width * spriteImage.scale)
            let imgHeight = Int(spriteImage.size.height * spriteImage.scale)
            self.cellWidth = imgWidth / self.columns

            let rowCount = max(1, (timestamps.count + self.columns - 1) / self.columns)
            self.cellHeight = rowCount > 0 ? imgHeight / rowCount : imgHeight
        }
    }

    /// 获取雪碧图和时间映射
    func fetch(bvid: String) async throws -> VideoShotResult {
        // index=1: 返回 JSON 格式时间戳
        let data = try await api.get(BiliAPI.videoShot, params: [
            "bvid": bvid,
            "index": 1
        ])

        // 获取雪碧图 URL（B站返回的 data 直接包含 image 和 index）
        let responseData: [String: Any]
        if let inner = data["data"] as? [String: Any] {
            responseData = inner
        } else {
            responseData = data
        }

        guard let imageArray = responseData["image"] as? [String],
              var spriteURLString = imageArray.first
        else {
            throw AppError.spriteSheetUnavailable
        }

        // 处理各种 URL 格式
        // 实测：B站返回 "//i0.hdslb.com/bfs/videoshot/xxx.jpg"（协议相对URL）
        if spriteURLString.hasPrefix("//") {
            spriteURLString = "https:" + spriteURLString
        } else if spriteURLString.hasPrefix("http://") {
            spriteURLString = spriteURLString.replacingOccurrences(of: "http://", with: "https://")
        }

        guard let spriteURL = URL(string: spriteURLString) else {
            throw AppError.spriteSheetUnavailable
        }

        // 获取时间戳数组
        guard let indexArray = responseData["index"] as? [Any] else {
            throw AppError.spriteSheetUnavailable
        }

        let timestamps = indexArray.compactMap { item -> Int? in
            if let num = item as? Int { return num }
            if let num = item as? Double { return Int(num) }
            return nil
        }

        // 下载雪碧图
        let (imageData, _) = try await URLSession.shared.data(from: spriteURL)
        guard let spriteImage = UIImage(data: imageData) else {
            throw AppError.spriteSheetUnavailable
        }

        var result = VideoShotResult(spriteImage: spriteImage, timestamps: timestamps)

        Logger.biliAPI.info("""
            雪碧图获取成功: \(timestamps.count) 帧, \
            \(Int(spriteImage.size.width * spriteImage.scale))×\(Int(spriteImage.size.height * spriteImage.scale))px, \
            \(result.columns)×\(result.rows) 网格, \
            \(result.cellWidth)×\(result.cellHeight)px/格, \
            \(Int(imageData.count / 1024))KB
            """)
        return result
    }
}
