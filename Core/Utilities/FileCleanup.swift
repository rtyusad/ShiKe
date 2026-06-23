import Foundation

/// 临时文件清理策略
/// - App 启动时清理残留孤儿 mp4
/// - App 进入后台时清理
/// - 过期雪碧图 TTL 清理
final class FileCleanup {

    private let fileManager = FileManager.default

    /// 临时 mp4 存放目录
    var tempMP4Dir: URL {
        fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TempMP4")
    }

    /// 雪碧图缓存目录
    var spriteSheetDir: URL {
        fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SpriteSheets")
    }

    // MARK: - 公开方法

    /// AC13: 清理所有孤儿临时文件
    /// 在 App 启动时、进入后台时调用
    func cleanupOrphanedFiles() {
        ensureDirectoryExists(at: tempMP4Dir)
        ensureDirectoryExists(at: spriteSheetDir)

        // 清理残留 mp4（正常路径已在提取完成后删除）
        removeAllFiles(in: tempMP4Dir, matching: { $0.pathExtension == "mp4" })

        // 清理过期雪碧图（AC04: 7天 TTL）
        cleanupExpiredFiles(in: spriteSheetDir, ttl: AppConstants.spriteSheetCacheTTL)
    }

    /// 删除单个文件（失败不抛异常）
    func deleteFile(at url: URL) {
        do {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        } catch {
            Logger.frameExtraction.warning("文件清理失败: \(url.lastPathComponent) - \(error)")
        }
    }

    /// 删除指定目录
    func deleteDirectory(at url: URL) {
        do {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        } catch {
            Logger.frameExtraction.warning("目录清理失败: \(url.lastPathComponent) - \(error)")
        }
    }

    // MARK: - 私有

    private func ensureDirectoryExists(at url: URL) {
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func removeAllFiles(in directory: URL, matching predicate: (URL) -> Bool) {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return }

        for url in contents where predicate(url) {
            deleteFile(at: url)
            Logger.frameExtraction.info("清理孤儿文件: \(url.lastPathComponent)")
        }
    }

    private func cleanupExpiredFiles(in directory: URL, ttl: TimeInterval) {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }

        let now = Date()
        for url in contents {
            guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
                  let modDate = attrs[.modificationDate] as? Date
            else { continue }

            if now.timeIntervalSince(modDate) > ttl {
                deleteFile(at: url)
                Logger.frameExtraction.info("清理过期缓存: \(url.lastPathComponent)")
            }
        }
    }
}
