import Foundation
import OSLog
/// GOP subsegment 下载器
/// 使用 HTTP Range 请求下载视频流的特定字节范围
///
/// AC11: 单个 GOP 下载超时 15s（URLSession 默认 60s 对 ~500KB 请求过长）
final class GOPDownloader {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = AppConstants.gopDownloadTimeout
        config.timeoutIntervalForResource = AppConstants.gopDownloadTimeout
        config.httpAdditionalHeaders = [
            "User-Agent": BiliAPI.userAgent
        ]
        self.session = URLSession(configuration: config)
    }

    /// 下载 init segment + sidx box（合并为一次请求以节省往返）
    /// Range 格式: "initStart-indexEnd"
    func downloadInitAndSidx(
        baseURL: String,
        initRange: String,
        indexRange: String
    ) async throws -> (initData: Data, sidxData: Data) {
        let initParts = initRange.split(separator: "-")
        let indexParts = indexRange.split(separator: "-")

        guard let initStart = initParts.first.flatMap({ Int64($0) }),
              let indexEnd = indexParts.last.flatMap({ Int64($0) }) else {
            throw AppError.gopDownloadFailed(0)
        }

        let rangeString = "\(initStart)-\(indexEnd)"

        guard let url = URL(string: baseURL) else {
            throw AppError.invalidURL(baseURL)
        }

        Logger.frameExtraction.debug("Range 下载 init+sidx: \(rangeString)")
        let data = try await session.rangeDownload(from: url, range: rangeString)

        // 分割 init 和 sidx
        let initLength = Int((indexParts.first.flatMap { Int64($0) } ?? 0) - initStart)
        let initData = data.prefix(initLength)
        let sidxData = data.suffix(from: initLength)

        Logger.frameExtraction.info("init+sidx 下载完成: \(Int(data.count / 1024))KB")
        return (initData: Data(initData), sidxData: Data(sidxData))
    }

    /// 下载单个 subsegment (GOP)
    func downloadSubsegment(
        baseURL: String,
        byteOffset: UInt64,
        byteLength: UInt32
    ) async throws -> Data {
        let rangeEnd = byteOffset + UInt64(byteLength) - 1
        let rangeString = "\(byteOffset)-\(rangeEnd)"

        guard let url = URL(string: baseURL) else {
            throw AppError.invalidURL(baseURL)
        }

        Logger.frameExtraction.debug("Range 下载 GOP: \(rangeString) (~\(byteLength/1024)KB)")
        let data = try await session.rangeDownload(from: url, range: rangeString)

        guard !data.isEmpty else {
            throw AppError.gopDownloadFailed(0)
        }

        return data
    }

    /// 下载 init segment only（用于 playurl 过期后重新获取）
    func downloadInit(baseURL: String, initRange: String) async throws -> Data {
        guard let url = URL(string: baseURL) else {
            throw AppError.invalidURL(baseURL)
        }
        return try await session.rangeDownload(from: url, range: initRange)
    }
}
