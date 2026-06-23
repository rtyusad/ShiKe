import Foundation

// MARK: - BV 号提取与校验

extension String {

    /// B 站 BV 号正则：BV + 10 位字母数字
    private static let bvPattern = #/BV[a-zA-Z0-9]{10}/#

    /// 从字符串中提取 BV 号
    /// 支持格式：
    /// - `https://www.bilibili.com/video/BV1xx411c7mD`
    /// - `https://b23.tv/xxxxx`
    /// - 纯 BV 号 `BV1xx411c7mD`
    var extractedBV: String? {
        // 直接匹配 BV 号
        if let match = try? String.bvPattern.firstMatch(in: self) {
            return String(match.0)
        }
        return nil
    }

    /// 是否为有效的 BV 号格式
    var isValidBV: Bool {
        extractedBV != nil
    }

    /// 是否为 b23.tv 短链接
    var isB23ShortLink: Bool {
        contains("b23.tv") || contains("b23.tv/")
    }

    /// 是否为 B 站链接（含 bilibili.com 或 b23.tv）
    var isBilibiliURL: Bool {
        contains("bilibili.com") || isB23ShortLink
    }
}
