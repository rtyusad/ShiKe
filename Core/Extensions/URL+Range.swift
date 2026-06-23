import Foundation

// MARK: - URL Range 请求便捷扩展

extension URLSession {

    /// 发起 Range 请求，下载指定字节范围
    /// - Parameters:
    ///   - url: 目标 URL
    ///   - range: 字节范围 (e.g. "0-1021")
    ///   - timeout: 超时时间
    /// - Returns: 下载的数据
    func rangeDownload(from url: URL, range: String, timeout: TimeInterval = 15) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("bytes=\(range)", forHTTPHeaderField: "Range")
        request.setValue(BiliAPI.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = timeout

        let (data, response) = try await data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.apiFailed(0, "非 HTTP 响应")
        }

        switch httpResponse.statusCode {
        case 200, 206:
            return data
        case 403, 410:
            throw AppError.gopURLExpired
        case 416:
            throw AppError.gopDownloadFailed(httpResponse.statusCode)
        default:
            throw AppError.apiFailed(httpResponse.statusCode, "Range 请求失败")
        }
    }
}
