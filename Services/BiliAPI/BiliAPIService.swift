import Foundation

/// B 站 API 基础 HTTP 客户端
/// 所有 B 站 API 调用都通过此 service 发出
/// 统一处理 User-Agent、超时、错误码
final class BiliAPIService {
    private let session: URLSession
    private let baseURL: String

    init(baseURL: String = BiliAPI.baseURL) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = AppConstants.apiTimeout
        config.timeoutIntervalForResource = AppConstants.apiTimeout
        config.httpAdditionalHeaders = [
            "User-Agent": BiliAPI.userAgent,
            "Accept": "application/json"
        ]
        self.session = URLSession(configuration: config)
        self.baseURL = baseURL
    }

    // MARK: - 通用 GET 请求

    /// 发起 GET 请求并解析 JSON 响应
    /// - Parameters:
    ///   - path: API 路径（e.g. "/x/web-interface/view"）
    ///   - params: 查询参数
    /// - Returns: 响应 JSON 字典
    func get(_ path: String, params: [String: Any]) async throws -> [String: Any] {
        var components = URLComponents(string: baseURL + path)
        components?.queryItems = params.compactMap { key, value in
            guard let stringValue = "\(value)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
                return nil
            }
            return URLQueryItem(name: key, value: stringValue)
        }

        guard let url = components?.url else {
            throw AppError.invalidURL(path)
        }

        Logger.biliAPI.debug("GET \(path)")

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.apiFailed(0, "非 HTTP 响应")
        }

        return try parseResponse(data: data, statusCode: httpResponse.statusCode)
    }

    /// 发起 GET 请求并返回原始 Data（用于二进制内容：雪碧图、pvdata、sidx）
    func getRaw(_ path: String, params: [String: Any]) async throws -> Data {
        var components = URLComponents(string: baseURL + path)
        components?.queryItems = params.compactMap { key, value in
            URLQueryItem(name: key, value: "\(value)")
        }

        guard let url = components?.url else {
            throw AppError.invalidURL(path)
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw AppError.apiFailed((response as? HTTPURLResponse)?.statusCode ?? 0, "请求失败")
        }

        return data
    }

    // MARK: - B 站 API 响应解析

    /// 解析 B 站统一 JSON 响应格式
    /// 格式: {"code": 0, "message": "0", "data": {...}}
    private func parseResponse(data: Data, statusCode: Int) throws -> [String: Any] {
        guard (200...299).contains(statusCode) else {
            throw AppError.apiFailed(statusCode, "HTTP \(statusCode)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AppError.apiFailed(statusCode, "无效的 JSON 响应")
        }

        let code = json["code"] as? Int ?? -1

        // B 站 -352: WBI 签名过期
        if code == -352 {
            throw AppError.wbiKeyExpired
        }

        // B 站 -404: 视频不存在
        if code == -404 {
            let msg = json["message"] as? String ?? "视频不存在"
            throw AppError.videoUnavailable(msg)
        }

        guard code == 0 else {
            let msg = json["message"] as? String ?? "未知错误"
            throw AppError.apiFailed(code, msg)
        }

        guard let dataDict = json["data"] as? [String: Any] else {
            throw AppError.apiFailed(code, "响应数据为空")
        }

        return dataDict
    }
}
