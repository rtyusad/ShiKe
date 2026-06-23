import UIKit
import AVFoundation
import OSLog
/// I 帧提取器
///
/// 使用 AVAssetImageGenerator 从本地 mini-mp4 提取高清 I 帧。
///
/// **重要**：AVAssetImageGenerator 仅用于本地 mp4 文件（moov atom 在文件头），
/// **不能**直接处理远程 DASH URL（fragmented MP4 的 moov 不在文件头）。
/// 这就是为什么需要先通过 sidx+GOP 方案下载拼装本地 mp4。
struct IFrameExtractor {

    enum ExtractionError: Error {
        case assetLoadFailed
        case imageGenerationFailed
        case noImageReturned
    }

    /// 从本地 mini-mp4 提取 I 帧
    /// - Parameters:
    ///   - mp4URL: 本地 mini-mp4 文件 URL
    ///   - at: 提取时间点（秒），通常为 0（GOP 的第一个 I 帧）
    /// - Returns: 高清截图 UIImage
    func extract(from mp4URL: URL, at timeSeconds: Double = 0) async throws -> UIImage {
        let asset = AVURLAsset(url: mp4URL)

        // 验证 asset 可读
        guard try await asset.load(.isReadable) else {
            throw ExtractionError.assetLoadFailed
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        // 请求最高质量
        generator.maximumSize = CGSize(width: 1920, height: 1080)

        let time = CMTime(seconds: timeSeconds, preferredTimescale: 600)

        return try await withCheckedThrowingContinuation { continuation in
            generator.generateCGImageAsynchronously(for: time) { cgImage, actualTime, error in
                if let error = error {
                    Logger.frameExtraction.error("I 帧提取失败: \(error)")
                    continuation.resume(throwing: ExtractionError.imageGenerationFailed)
                    return
                }

                guard let cgImage = cgImage else {
                    continuation.resume(throwing: ExtractionError.noImageReturned)
                    return
                }

                let image = UIImage(cgImage: cgImage)
                Logger.frameExtraction.info("""
                    I 帧提取成功: \(Int(image.size.width))×\(Int(image.size.height)), \
                    time=\(String(format: "%.2f", CMTimeGetSeconds(actualTime)))s
                    """)
                continuation.resume(returning: image)
            }
        }
    }
}
