import Foundation
import CommonCrypto
import OSLog
/// B 站 WBI 签名器 (actor)
///
/// 签名流程：
/// 1. 从 nav 接口获取 img_key 和 sub_key
/// 2. 拼接 → MD5 → 取前 32 位 → mixin_key
/// 3. 对请求参数按 key 排序 → 拼接 → 追加 mixin_key → MD5 → w_rid
/// 4. 追加 wts (当前秒级时间戳)
///
/// 缓存策略：mixin_key 缓存 4 小时（AC），过期自动刷新
/// 错误恢复：遇 -352 错误码时调用 invalidateKey() 强制刷新
///
/// 参考: https://github.com/SocialSisterYi/bilibili-API-collect/blob/master/docs/misc/sign/wbi.md
actor WbiSigner {
    private let api: BiliAPIService
    private var cachedKey: String?
    private var lastFetchTime: Date = .distantPast

    init(api: BiliAPIService = BiliAPIService()) {
        self.api = api
    }

    // MARK: - 公开接口

    /// 对参数字典进行 WBI 签名
    func sign(_ params: [String: Any]) async throws -> [String: Any] {
        let mixinKey = try await getMixinKey()
        var signed = params

        // wts: 当前秒级时间戳
        let wts = Int(Date().timeIntervalSince1970)
        signed["wts"] = wts

        // 按 key 排序后拼接参数字符串
        let sortedKeys = signed.keys.sorted()
        let queryString = sortedKeys.compactMap { key -> String? in
            guard let value = signed[key] else { return nil }
            return "\(key)=\(value)"
        }.joined(separator: "&")

        // w_rid = MD5(queryString + mixin_key)
        let raw = queryString + mixinKey
        signed["w_rid"] = raw.md5

        return signed
    }

    /// 强制刷新 mixin_key（B 站返回 -352 时调用）
    func invalidateKey() {
        cachedKey = nil
        lastFetchTime = .distantPast
        Logger.biliAPI.info("WBI mixin_key 已失效，已标记为待刷新")
    }

    // MARK: - 私有

    /// 获取 mixin_key（带缓存）
    private func getMixinKey() async throws -> String {
        // 缓存命中且未过期
        if let key = cachedKey,
           Date().timeIntervalSince(lastFetchTime) < AppConstants.wbiKeyTTL {
            return key
        }

        Logger.biliAPI.debug("获取 WBI mixin_key...")
        let key = try await fetchAndComputeMixinKey()
        cachedKey = key
        lastFetchTime = Date()
        Logger.biliAPI.debug("WBI mixin_key 已刷新")
        return key
    }

    /// 从 nav 接口获取 img_key + sub_key → MD5 拼接
    /// 注意：nav API 即使返回 code=-101（未登录），
    /// data 中仍包含 wbi_img 信息，所以需要直接解析 JSON 而不检查 code
    private func fetchAndComputeMixinKey() async throws -> String {
        // 直接请求 nav，不经过 BiliAPIService（后者会检查 code==0）
        let url = URL(string: BiliAPI.baseURL + BiliAPI.nav)!
        var request = URLRequest(url: url)
        request.setValue(BiliAPI.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.bilibili.com", forHTTPHeaderField: "Referer")
        request.timeoutInterval = 15

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let innerData = json["data"] as? [String: Any],
              let wbiImg = innerData["wbi_img"] as? [String: Any],
              let imgURL = wbiImg["img_url"] as? String,
              let subURL = wbiImg["sub_url"] as? String
        else {
            throw AppError.wbiSignFailed
        }

        // 提取文件名（去掉路径和扩展名）
        let imgKey = (imgURL as NSString)
            .lastPathComponent
            .replacingOccurrences(of: ".png", with: "")
        let subKey = (subURL as NSString)
            .lastPathComponent
            .replacingOccurrences(of: ".png", with: "")

        // 拼接 → MD5 → 取前 32 位
        let rawKey = imgKey + subKey
        return rawKey.md5.prefix(32).lowercased()
    }
}

// MARK: - MD5 扩展

private extension String {
    var md5: String {
        let data = Data(self.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        data.withUnsafeBytes { bytes in
            _ = CC_MD5(bytes.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
