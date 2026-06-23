import Foundation

/// 全局应用错误类型
/// 所有用户可见的错误都需要 localizedDescription
enum AppError: LocalizedError {
    // MARK: - B 站 API
    case invalidURL(String)
    case apiFailed(Int, String)
    case videoUnavailable(String)
    case wbiSignFailed
    case wbiKeyExpired

    // MARK: - 帧提取
    case spriteSheetUnavailable
    case sidxParseFailed(String)
    case gopDownloadFailed(Int)
    case gopURLExpired
    case mp4AssemblyFailed
    case iframeExtractionFailed

    // MARK: - 业务
    case duplicateRecipe(String)
    case freeSlotExhausted
    case storageFull
    case networkUnavailable

    // MARK: - LocalizedError

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "无效的链接：\(url)"
        case .apiFailed(let code, let msg):
            return "接口请求失败 (\(code))：\(msg)"
        case .videoUnavailable(let bv):
            return "视频不可用：\(bv)，请确认链接是否正确"
        case .wbiSignFailed:
            return "签名验证失败，请重试"
        case .wbiKeyExpired:
            return "签名密钥已过期，正在自动刷新..."
        case .spriteSheetUnavailable:
            return "该视频暂不支持帧预览"
        case .sidxParseFailed(let detail):
            return "视频流解析失败：\(detail)"
        case .gopDownloadFailed(let code):
            return "截图下载失败 (\(code))"
        case .gopURLExpired:
            return "视频链接已过期，正在重新获取..."
        case .mp4AssemblyFailed:
            return "视频片段拼装失败"
        case .iframeExtractionFailed:
            return "高清截图提取失败"
        case .duplicateRecipe(let title):
            return "「\(title)」已保存过，请勿重复添加"
        case .freeSlotExhausted:
            return "免费额度已用完（\(AppConstants.freeSlotLimit) 个），升级获取无限空间"
        case .storageFull:
            return "存储空间不足，请清理后重试"
        case .networkUnavailable:
            return "网络连接不可用，请检查网络设置"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .wbiSignFailed, .wbiKeyExpired:
            return "请稍后重试"
        case .spriteSheetUnavailable:
            return "您可以使用手动截图模式添加食谱"
        case .sidxParseFailed:
            return "将使用预览图代替高清截图"
        case .gopDownloadFailed:
            return "已跳过该帧，其他步骤不受影响"
        case .gopURLExpired:
            return "系统将自动重新获取视频流"
        case .freeSlotExhausted:
            return "¥8 终身买断，一次付费永久使用"
        case .networkUnavailable:
            return "请连接 Wi-Fi 或蜂窝网络后重试"
        case .duplicateRecipe:
            return "您可以在食谱库中查看已保存的食谱"
        default:
            return "请稍后重试"
        }
    }
}
