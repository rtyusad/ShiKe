import UIKit
import CoreGraphics
import OSLog
/// 雪碧图解析器
///
/// 将 B 站 videoshot API 返回的雪碧图大图切分为独立的帧缩略图。
/// B站固定 10 列，行数 = ceil(帧数 / 10)。
/// 格子尺寸 = 图宽÷列数 × 图高÷行数（从实际图像尺寸动态计算）。
struct SpriteSheetParser {

    /// 单帧数据
    struct FrameThumbnail: Identifiable {
        public var id: Int { timestampSeconds }
        let image: UIImage
        let timestampSeconds: Int
        let column: Int
        let row: Int
    }

    /// 切分雪碧图
    /// - Parameters:
    ///   - spriteImage: 完整的雪碧图 UIImage
    ///   - timestamps: 时间戳数组（秒），按格子顺序排列（从左到右、从上到下）
    ///   - columns: 网格列数（B站固定 = 10）
    /// - Returns: 帧缩略图数组
    func parse(
        spriteImage: UIImage,
        timestamps: [Int],
        columns: Int = 10
    ) -> [FrameThumbnail] {
        guard let cgImage = spriteImage.cgImage else {
            Logger.frameExtraction.error("雪碧图 CGImage 获取失败")
            return []
        }

        let totalFrames = timestamps.count
        let rows = max(1, (totalFrames + columns - 1) / columns)

        // 从图像尺寸动态计算格子大小
        let cellWidth = cgImage.width / columns
        let cellHeight = cgImage.height / rows

        guard cellWidth > 0, cellHeight > 0 else {
            Logger.frameExtraction.error("雪碧图格子计算异常: \(cgImage.width)×\(cgImage.height) / \(columns)×\(rows)")
            return []
        }

        var frames: [FrameThumbnail] = []

        for (index, timestamp) in timestamps.enumerated() {
            let column = index % columns
            let row = index / columns
            let x = column * cellWidth
            let y = row * cellHeight

            // 边界检查
            guard x + cellWidth <= cgImage.width,
                  y + cellHeight <= cgImage.height else {
                Logger.frameExtraction.warning("帧 \(index) 超出雪碧图边界: (\(x),\(y))")
                continue
            }

            let cropRect = CGRect(x: x, y: y, width: cellWidth, height: cellHeight)
            guard let cropped = cgImage.cropping(to: cropRect) else { continue }

            // 绘制到独立 bitmap 上下文，切断与原始雪碧图的 CGImage 共享引用
            // 否则 SwiftUI 渲染多个缩略图时会因 Core Animation 缓冲复用导致画面叠加
            UIGraphicsBeginImageContextWithOptions(cropRect.size, false, 1.0)
            UIImage(cgImage: cropped, scale: 1, orientation: spriteImage.imageOrientation).draw(at: .zero)
            let frameImage = UIGraphicsGetImageFromCurrentImageContext()
                ?? UIImage(cgImage: cropped, scale: 1, orientation: spriteImage.imageOrientation)
            UIGraphicsEndImageContext()

            frames.append(FrameThumbnail(
                image: frameImage,
                timestampSeconds: timestamp,
                column: column,
                row: row
            ))
        }

        Logger.frameExtraction.info("""
            雪碧图切分完成: \(frames.count)/\(totalFrames) 帧 \
            (\(cellWidth)×\(cellHeight)px, \(columns)×\(rows) 网格)
            """)
        return frames
    }
}
