import UIKit
import Foundation

/// 云端 VLM (Vision Language Model) 服务
///
/// MVP 阶段使用 DashScope Qwen-VL API 将步骤截图转化为文字描述。
/// V1.1 迁移至 Core ML 本地推理。
///
/// 支持的后端：
/// - dashscope: 阿里云 DashScope (qwen-vl-plus)
/// - apimart: APIMart 代理 (gemini-3-pro / qwen-vl)
///
/// 设计为 actor 以避免阻塞 MainActor。
/// 支持与帧提取管线流水线并行。
actor VLMService {

    // MARK: - 配置

    enum Backend {
        case dashscope(apiKey: String)
        case apimart(apiKey: String, model: String)
        case custom(url: String, apiKey: String, model: String)
    }

    private let backend: Backend

    /// 默认烹饪步骤分析 prompt
    private static let cookingPrompt = """
    你是一个专业的中餐烹饪助手。请分析这张烹饪步骤截图，用中文输出以下内容：

    1. 描述当前步骤中进行的操作（如：切菜、爆香、翻炒、调味等）
    2. 识别画面中可见的主要食材和调料
    3. 如果有明显的火候/油温/颜色变化的细节，请指出
    4. 如果适用，提供一条实用的烹饪小贴士

    请以 JSON 格式回复，不要包含其他文字：
    {"description": "步骤操作描述（15-40字）", "tip": "小贴士（10-25字，如无则为null）"}
    """

    // MARK: - 初始化

    init(backend: Backend = .dashscope(apiKey: "")) {
        self.backend = backend
    }

    /// 便捷初始化：DashScope
    init(dashscopeAPIKey: String) {
        self.backend = .dashscope(apiKey: dashscopeAPIKey)
    }

    /// 便捷初始化：APIMart
    init(apimartKey: String, model: String = "qwen-vl-plus") {
        self.backend = .apimart(apiKey: apimartKey, model: model)
    }

    // MARK: - 公开接口

    /// 分析单张步骤截图
    func describe(image: UIImage) async throws -> StepDescription {
        Logger.vlm.info("VLM 分析请求")

        let base64 = try encodeImageForAPI(image)

        let response: [String: Any] = try await sendRequest(
            imageBase64: base64,
            prompt: Self.cookingPrompt
        )

        return try parseResponse(response)
    }

    /// 批量分析（顺序调用，避免 API 限流）
    func describeBatch(images: [UIImage]) async throws -> [StepDescription] {
        var results: [StepDescription] = []
        for (index, image) in images.enumerated() {
            Logger.vlm.debug("VLM 批量: \(index + 1)/\(images.count)")
            do {
                let desc = try await describe(image: image)
                results.append(desc)
            } catch {
                Logger.vlm.error("VLM 帧 \(index + 1) 失败: \(error)")
                // 单帧失败不阻塞整体
                results.append(StepDescription(
                    descriptionText: "步骤 \(index + 1)", tipNote: nil
                ))
            }
            // 顺序调用间的小延迟避免限流
            if index < images.count - 1 {
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
        return results
    }

    // MARK: - 私有：图片编码

    private func encodeImageForAPI(_ image: UIImage) throws -> String {
        // 限制最大分辨率以控制 token 消耗
        let maxDimension: CGFloat = 1024
        let resized: UIImage
        if image.size.width > maxDimension || image.size.height > maxDimension {
            let scale = min(maxDimension / image.size.width, maxDimension / image.size.height)
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            resized = UIGraphicsGetImageFromCurrentImageContext() ?? image
            UIGraphicsEndImageContext()
        } else {
            resized = image
        }

        guard let jpegData = resized.jpegData(compressionQuality: 0.85) else {
            throw AppError.apiFailed(0, "图片编码失败")
        }

        return jpegData.base64EncodedString()
    }

    // MARK: - 私有：API 请求

    private func sendRequest(imageBase64: String, prompt: String) async throws -> [String: Any] {
        switch backend {
        case .dashscope(let apiKey):
            return try await callDashScope(apiKey: apiKey, imageBase64: imageBase64, prompt: prompt)
        case .apimart(let apiKey, let model):
            return try await callAPIMart(apiKey: apiKey, model: model, imageBase64: imageBase64, prompt: prompt)
        case .custom(let url, let apiKey, let model):
            return try await callCustom(url: url, apiKey: apiKey, model: model, imageBase64: imageBase64, prompt: prompt)
        }
    }

    /// DashScope API (阿里云 Qwen-VL)
    /// POST https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions
    private func callDashScope(
        apiKey: String, imageBase64: String, prompt: String
    ) async throws -> [String: Any] {
        let url = URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": "qwen-vl-plus",
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "text", "text": prompt],
                    ["type": "image_url", "image_url": [
                        "url": "data:image/jpeg;base64,\(imageBase64)"
                    ]]
                ]
            ]],
            "max_tokens": 300,
            "temperature": 0.3,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw AppError.apiFailed(
                (response as? HTTPURLResponse)?.statusCode ?? 0,
                "VLM API 请求失败"
            )
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AppError.apiFailed(0, "VLM 响应解析失败")
        }

        return json
    }

    /// APIMart 代理 API
    private func callAPIMart(
        apiKey: String, model: String, imageBase64: String, prompt: String
    ) async throws -> [String: Any] {
        let url = URL(string: "https://api.apimart.ai/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": model,
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "text", "text": prompt],
                    ["type": "image_url", "image_url": [
                        "url": "data:image/jpeg;base64,\(imageBase64)"
                    ]]
                ]
            ]],
            "max_tokens": 300,
            "temperature": 0.3,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw AppError.apiFailed(
                (response as? HTTPURLResponse)?.statusCode ?? 0,
                "APIMart 请求失败"
            )
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AppError.apiFailed(0, "APIMart 响应解析失败")
        }

        return json
    }

    /// 自定义 API 端点
    private func callCustom(
        url: String, apiKey: String, model: String, imageBase64: String, prompt: String
    ) async throws -> [String: Any] {
        guard let endpoint = URL(string: url) else {
            throw AppError.invalidURL(url)
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": model,
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "text", "text": prompt],
                    ["type": "image_url", "image_url": [
                        "url": "data:image/jpeg;base64,\(imageBase64)"
                    ]]
                ]
            ]],
            "max_tokens": 300,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw AppError.apiFailed(
                (response as? HTTPURLResponse)?.statusCode ?? 0,
                "自定义 VLM API 请求失败"
            )
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AppError.apiFailed(0, "响应解析失败")
        }

        return json
    }

    // MARK: - 私有：响应解析

    /// 解析 VLM 响应 → StepDescription
    /// 支持 OpenAI 兼容格式: {"choices": [{"message": {"content": "..."}}]}
    private func parseResponse(_ json: [String: Any]) throws -> StepDescription {
        // OpenAI 兼容格式
        if let choices = json["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any],
           let content = message["content"] as? String {
            return try parseContent(content)
        }

        // DashScope 原生格式
        if let output = json["output"] as? [String: Any],
           let choices = output["choices"] as? [[String: Any]],
           let message = choices.first?["message"] as? [String: Any],
           let content = message["content"] as? String {
            return try parseContent(content)
        }

        Logger.vlm.error("无法解析 VLM 响应: \(json)")
        throw AppError.apiFailed(0, "VLM 响应格式不匹配")
    }

    /// 解析 content 文本中的 JSON
    private func parseContent(_ content: String) throws -> StepDescription {
        // 尝试直接解析 JSON
        if let data = content.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let desc = dict["description"] as? String {
            return StepDescription(
                descriptionText: desc,
                tipNote: dict["tip"] as? String
            )
        }

        // 尝试提取 ```json ... ``` 代码块中的 JSON
        if let jsonStart = content.range(of: "```json"),
           let jsonEnd = content.range(of: "```", range: jsonStart.upperBound..<content.endIndex) {
            let jsonStr = String(content[jsonStart.upperBound..<jsonEnd.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let data = jsonStr.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let desc = dict["description"] as? String {
                return StepDescription(descriptionText: desc, tipNote: dict["tip"] as? String)
            }
        }

        // 降级：直接使用原始文本作为描述
        let cleaned = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        Logger.vlm.warning("VLM 返回非 JSON 格式，使用原始文本")
        return StepDescription(
            descriptionText: String(cleaned.prefix(100)),
            tipNote: nil
        )
    }
}

/// 步骤描述结果
struct StepDescription {
    let descriptionText: String
    let tipNote: String?
}
