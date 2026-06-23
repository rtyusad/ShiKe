import OSLog

/// 结构化日志系统
/// 按 category 分类，支持 Console.app 实时查看和 sysdiagnose 收集
extension Logger {
    private static let subsystem = "com.shike.ios"

    /// 帧提取管线日志
    static let frameExtraction = Logger(subsystem: subsystem, category: "FrameExtraction")
    /// B 站 API 调用日志
    static let biliAPI = Logger(subsystem: subsystem, category: "BiliAPI")
    /// 食谱数据操作日志
    static let recipe = Logger(subsystem: subsystem, category: "Recipe")
    /// 云端 VLM 调用日志
    static let vlm = Logger(subsystem: subsystem, category: "VLM")
    /// IAP 付费日志
    static let iap = Logger(subsystem: subsystem, category: "IAP")
    /// App 生命周期日志
    static let lifecycle = Logger(subsystem: subsystem, category: "Lifecycle")
}
