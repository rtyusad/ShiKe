import Foundation

/// B 站 API 端点常量
/// 参考: https://github.com/SocialSisterYi/bilibili-API-collect
enum BiliAPI {
    /// B 站主站
    static let baseURL = "https://api.bilibili.com"

    // MARK: - 公开 API（无需签名）

    /// 视频信息 API
    /// GET /x/web-interface/view?bvid={BV号}
    static let videoInfo = "/x/web-interface/view"

    /// 视频雪碧图 API（零签名）
    /// GET /x/player/videoshot?bvid={BV号}&index=1
    static let videoShot = "/x/player/videoshot"

    /// WBI 密钥获取（nav 接口）
    /// GET /x/web-interface/nav
    static let nav = "/x/web-interface/nav"

    // MARK: - 需 WBI 签名的 API

    /// 视频流 URL API（需 WBI 签名）
    /// GET /x/player/playurl?bvid={BV号}&cid={cid}&fnval=16&fnver=0&fourk=1
    static let playURL = "/x/player/playurl"

    // MARK: - 请求参数

    /// DASH 格式标志（获取分段流 + sidx）
    static let fnvalDASH = 16
    /// 支持 4K
    static let fourk = 1
    /// 支持 1080p+
    static let fnver = 0

    // MARK: - User-Agent

    /// 模拟移动端 UA（降低被限流风险）
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15"
}
