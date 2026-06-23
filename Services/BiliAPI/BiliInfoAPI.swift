import Foundation

/// B 站视频信息 API
/// GET /x/web-interface/view?bvid={BV号}
/// 返回视频标题、UP 主、时长、CID 等元数据
struct BiliInfoAPI {
    private let api: BiliAPIService

    init(api: BiliAPIService = BiliAPIService()) {
        self.api = api
    }

    struct VideoInfo {
        let bvid: String
        let title: String
        let authorName: String
        let authorMid: Int
        let durationSeconds: Int
        let coverURL: String
        let cid: Int
        let description: String?
    }

    /// 获取视频元数据
    func fetch(bvid: String) async throws -> VideoInfo {
        let data = try await api.get(BiliAPI.videoInfo, params: ["bvid": bvid])

        guard let stat = data["stat"] as? [String: Any] else {
            throw AppError.videoUnavailable(bvid)
        }

        let title = (data["title"] as? String) ?? "未知标题"
        let duration = data["duration"] as? Int ?? 0
        let cid = data["cid"] as? Int ?? 0

        guard let owner = data["owner"] as? [String: Any],
              let authorName = owner["name"] as? String,
              let authorMid = owner["mid"] as? Int else {
            throw AppError.videoUnavailable(bvid)
        }

        guard cid > 0 else {
            throw AppError.videoUnavailable("\(bvid): 无法获取 cid")
        }

        return VideoInfo(
            bvid: bvid,
            title: title,
            authorName: authorName,
            authorMid: authorMid,
            durationSeconds: duration,
            coverURL: (data["pic"] as? String) ?? "",
            cid: cid,
            description: data["desc"] as? String
        )
    }
}
