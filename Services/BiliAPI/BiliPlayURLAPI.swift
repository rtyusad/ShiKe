import Foundation

/// B 站视频流 URL API（需 WBI 签名 + 用户 cookie）
/// GET /x/player/playurl?bvid={BV号}&cid={cid}&fnval=16&fnver=0&fourk=1
/// 返回 DASH 格式视频流 URL + SegmentBase（含 sidx box 定位信息）
struct BiliPlayURLAPI {
    private let api: BiliAPIService
    private let signer: WbiSigner

    init(api: BiliAPIService = BiliAPIService(), signer: WbiSigner) {
        self.api = api
        self.signer = signer
    }

    struct SegmentBase {
        /// init segment 的字节范围 (e.g. "0-1021")
        let initializationRange: String
        /// sidx box 的字节范围 (e.g. "1022-5985")
        let indexRange: String
        /// 基础流 URL
        let baseURL: String
        /// 流时长（秒）
        let duration: Double
        /// 码率 (bps)
        let bandwidth: Int
        /// 编码格式 (e.g. "avc1.640028")
        let codecs: String
        /// 分辨率宽度
        let width: Int
        /// 分辨率高度
        let height: Int

        /// 解析 initialization range 的起止字节
        var initStart: Int64 {
            let parts = initializationRange.split(separator: "-")
            return Int64(parts.first ?? "0") ?? 0
        }

        var initEnd: Int64 {
            let parts = initializationRange.split(separator: "-")
            return Int64(parts.last ?? "0") ?? 0
        }

        /// 解析 index range 的起止字节
        var indexStart: Int64 {
            let parts = indexRange.split(separator: "-")
            return Int64(parts.first ?? "0") ?? 0
        }

        var indexEnd: Int64 {
            let parts = indexRange.split(separator: "-")
            return Int64(parts.last ?? "0") ?? 0
        }
    }

    /// 获取视频流 URL + SegmentBase
    /// 优先选择 1080p 清晰度，其次 720p，最少 480p
    func fetch(cid: Int, bvid: String) async throws -> SegmentBase {
        var params: [String: Any] = [
            "bvid": bvid,
            "cid": cid,
            "fnval": BiliAPI.fnvalDASH,
            "fnver": BiliAPI.fnver,
            "fourk": BiliAPI.fourk
        ]

        // WBI 签名
        let signedParams = try await signer.sign(params)

        let data = try await api.get(BiliAPI.playURL, params: signedParams)

        // 解析 DASH 视频流
        guard let dash = data["dash"] as? [String: Any],
              let videoArray = dash["video"] as? [[String: Any]] else {
            throw AppError.apiFailed(0, "视频流数据为空")
        }

        // 选择最佳清晰度：1080p > 720p > 480p
        let sortedVideos = videoArray.sorted { a, b in
            let widthA = a["width"] as? Int ?? 0
            let widthB = b["width"] as? Int ?? 0
            return widthA > widthB
        }

        guard let video = sortedVideos.first else {
            throw AppError.videoUnavailable("无可用的视频流")
        }

        guard let segmentBase = video["segment_base"] as? [String: Any],
              let initRange = segmentBase["initialization"] as? String,
              let indexRange = segmentBase["index_range"] as? String
        else {
            throw AppError.apiFailed(0, "视频流缺少 SegmentBase 信息")
        }

        guard let baseURL = video["base_url"] as? String ?? video["baseUrl"] as? String else {
            throw AppError.apiFailed(0, "视频流缺少 base_url")
        }

        let result = SegmentBase(
            initializationRange: initRange,
            indexRange: indexRange,
            baseURL: baseURL.replacingOccurrences(of: "http://", with: "https://"),
            duration: video["duration"] as? Double ?? 0,
            bandwidth: video["bandwidth"] as? Int ?? 0,
            codecs: video["codecs"] as? String ?? "",
            width: video["width"] as? Int ?? 0,
            height: video["height"] as? Int ?? 0
        )

        Logger.biliAPI.info("""
            DASH 流获取成功: \(result.width)×\(result.height), \
            init=\(initRange), index=\(indexRange), \
            bandwidth=\(result.bandwidth/1000)kbps
            """)

        return result
    }
}
