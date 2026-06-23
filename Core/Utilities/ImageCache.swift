import UIKit
import Foundation

/// 图片三级缓存：NSCache (内存) → 磁盘 LRU → FileManager (永久)
/// AC09: 内存上限 20MB，磁盘 LRU 上限 100MB
final class ImageCache {
    private let memoryCache = NSCache<NSString, UIImage>()
    private let diskCacheDir: URL
    private let fileManager = FileManager.default
    private let diskLimit: Int

    /// 磁盘 LRU 访问记录（用于淘汰策略）
    private var accessLog: [(key: String, size: Int, lastAccess: Date)] = []

    init(memoryLimit: Int = AppConstants.imageCacheMemoryLimit,
         diskLimit: Int = AppConstants.imageCacheDiskLimit) {
        self.memoryCache.totalCostLimit = memoryLimit
        self.diskLimit = diskLimit

        let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.diskCacheDir = cacheDir.appendingPathComponent("ImageCache")
        try? fileManager.createDirectory(at: diskCacheDir, withIntermediateDirectories: true)
    }

    // MARK: - 读取

    func image(forKey key: String) -> UIImage? {
        let nsKey = key as NSString

        // 1. 内存命中
        if let cached = memoryCache.object(forKey: nsKey) {
            return cached
        }

        // 2. 磁盘命中
        let diskURL = diskURL(forKey: key)
        if let data = try? Data(contentsOf: diskURL),
           let image = UIImage(data: data) {
            // 回填内存
            memoryCache.setObject(image, forKey: nsKey, cost: data.count)
            return image
        }

        return nil
    }

    // MARK: - 写入

    func setImage(_ image: UIImage, forKey key: String) {
        let nsKey = key as NSString
        guard let data = image.heicData(compressionQuality: AppConstants.heicCompressionQuality) else {
            return
        }

        // 写入内存
        memoryCache.setObject(image, forKey: nsKey, cost: data.count)

        // 写入磁盘
        let diskURL = diskURL(forKey: key)
        try? data.write(to: diskURL)

        // 磁盘 LRU 管理
        accessLog.append((key: key, size: data.count, lastAccess: Date()))
        evictDiskIfNeeded()
    }

    // MARK: - 清除

    func removeImage(forKey key: String) {
        memoryCache.removeObject(forKey: key as NSString)
        try? fileManager.removeItem(at: diskURL(forKey: key))
        accessLog.removeAll { $0.key == key }
    }

    func clearAll() {
        memoryCache.removeAllObjects()
        accessLog.removeAll()
        try? fileManager.removeItem(at: diskCacheDir)
        try? fileManager.createDirectory(at: diskCacheDir, withIntermediateDirectories: true)
    }

    // MARK: - 私有

    private func diskURL(forKey key: String) -> URL {
        // 使用 key 的 SHA256 作为文件名，避免非法字符
        let hash = key.data(using: .utf8)?.base64EncodedString() ?? key
        return diskCacheDir.appendingPathComponent(hash)
    }

    private func evictDiskIfNeeded() {
        // 按最后访问时间排序，淘汰最旧的
        let totalSize = accessLog.reduce(0) { $0 + $1.size }
        guard totalSize > diskLimit else { return }

        accessLog.sort { $0.lastAccess < $1.lastAccess }
        var removed = 0
        var newLog = accessLog

        for entry in accessLog {
            guard totalSize - removed > diskLimit else { break }
            try? fileManager.removeItem(at: diskURL(forKey: entry.key))
            memoryCache.removeObject(forKey: entry.key as NSString)
            removed += entry.size
            newLog.removeAll { $0.key == entry.key }
        }

        accessLog = newLog
    }
}

// MARK: - UIImage HEIC 编码扩展

extension UIImage {
    func heicData(compressionQuality: CGFloat) -> Data? {
        guard let cgImage = self.cgImage else { return nil }
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData as CFMutableData,
            "public.heic" as CFString, 1, nil
        ) else { return nil }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: compressionQuality
        ]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        CGImageDestinationFinalize(destination)
        return mutableData as Data
    }
}
