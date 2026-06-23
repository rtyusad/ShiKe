import Foundation

/// 全局应用常量
enum AppConstants {
    // MARK: - 免费额度
    /// 免费用户最大食谱数量
    static let freeSlotLimit = 3

    // MARK: - 定价
    /// 终身买断价格（人民币）
    static let lifetimePrice: Decimal = 8.0
    /// StoreKit 2 Product ID
    static let lifetimeProductID = "com.shike.ios.lifetime"

    // MARK: - 存储限制
    /// NSCache 内存上限
    static let imageCacheMemoryLimit: Int = 20 * 1024 * 1024  // 20 MB
    /// 磁盘 LRU 缓存上限
    static let imageCacheDiskLimit: Int = 100 * 1024 * 1024   // 100 MB
    /// HEIC 压缩质量
    static let heicCompressionQuality: CGFloat = 0.85
    /// 雪碧图缓存 TTL
    static let spriteSheetCacheTTL: TimeInterval = 7 * 24 * 3600

    // MARK: - 网络
    /// GOP 下载超时
    static let gopDownloadTimeout: TimeInterval = 15.0
    /// 通用 API 超时
    static let apiTimeout: TimeInterval = 30.0

    // MARK: - 业务约束
    /// 每食谱最少步骤数
    static let minStepsPerRecipe = 2
    /// 每食谱最多步骤数
    static let maxStepsPerRecipe = 50
    /// 食谱标题最大长度
    static let maxTitleLength = 100
    /// 昵称最小/最大长度
    static let nicknameMinLength = 2
    static let nicknameMaxLength = 20
    /// WBI mixin_key 缓存 TTL
    static let wbiKeyTTL: TimeInterval = 4 * 3600
    /// playurl 流 URL 有效期
    static let playURLTTL: TimeInterval = 120 * 60
}
