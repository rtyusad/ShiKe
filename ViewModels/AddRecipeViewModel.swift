import SwiftUI
import Observation

/// 添加食谱流程 ViewModel
/// 管理从粘贴链接到保存食谱的完整生命周期
@MainActor
@Observable
final class AddRecipeViewModel {
    private let biliAPI: BiliAPIService
    private let frameExtractionActor: FrameExtractionActor
    private let vlmService: VLMService
    private let recipeRepo: RecipeRepository
    private let networkMonitor: NetworkMonitor

    // MARK: - 状态

    enum FlowState {
        case urlInput           // 粘贴链接
        case fetching           // 获取视频信息+雪碧图
        case frameBrowsing      // 浏览帧 + 标记步骤
        case generating         // sidx+GOP 高清提取中
        case reviewing          // 步骤确认
        case saved              // 保存完成
    }

    private(set) var flowState: FlowState = .urlInput
    private(set) var urlText: String = ""
    private(set) var error: AppError?

    // 视频信息
    private(set) var videoInfo: BiliInfoAPI.VideoInfo?
    private(set) var frameThumbnails: [SpriteSheetParser.FrameThumbnail] = []
    private(set) var markedTimestamps: [Int] = []

    // 高清提取进度
    private(set) var extractionProgress: String = ""
    private(set) var extractedImages: [UIImage] = []
    private(set) var stepDescriptions: [StepDescription] = []

    // 提取任务（用于取消）
    private var extractionTask: Task<Void, Never>?

    init(
        biliAPI: BiliAPIService,
        frameExtractionActor: FrameExtractionActor,
        vlmService: VLMService,
        recipeRepo: RecipeRepository,
        networkMonitor: NetworkMonitor
    ) {
        self.biliAPI = biliAPI
        self.frameExtractionActor = frameExtractionActor
        self.vlmService = vlmService
        self.recipeRepo = recipeRepo
        self.networkMonitor = networkMonitor
    }

    // MARK: - 输入

    /// 更新链接文本
    func updateURL(_ text: String) {
        urlText = text
        error = nil
    }

    /// 获取视频信息 + 雪碧图（阶段一：零下载）
    func fetchVideo() async {
        guard let bv = urlText.extractedBV, urlText.isBilibiliURL else {
            error = .invalidURL(urlText)
            return
        }

        // 检查是否重复
        if let existing = try? await recipeRepo.findByBV(bv) {
            error = .duplicateRecipe(existing.title)
            return
        }

        flowState = .fetching
        error = nil

        do {
            let infoAPI = BiliInfoAPI()
            let shotAPI = BiliVideoShotAPI()

            async let info = infoAPI.fetch(bvid: bv)
            async let shot = shotAPI.fetch(bvid: bv)

            let (videoInfo, shotResult) = try await (info, shot)

            let parser = SpriteSheetParser()
            let frames = parser.parse(
                spriteImage: shotResult.spriteImage,
                timestamps: shotResult.timestamps
            )

            self.videoInfo = videoInfo
            self.frameThumbnails = frames
            self.flowState = .frameBrowsing

        } catch let error as AppError {
            self.error = error
            self.flowState = .urlInput
        } catch {
            self.error = .apiFailed(0, error.localizedDescription)
            self.flowState = .urlInput
        }
    }

    /// 标记/取消标记帧
    func toggleMark(timestamp: Int) {
        if let index = markedTimestamps.firstIndex(of: timestamp) {
            markedTimestamps.remove(at: index)
        } else {
            markedTimestamps.append(timestamp)
            markedTimestamps.sort()
        }
    }

    /// 是否已标记
    func isMarked(_ timestamp: Int) -> Bool {
        markedTimestamps.contains(timestamp)
    }

    /// 生成步骤卡片（阶段二：sidx+GOP 高清提取 + VLM）
    func generateSteps() async {
        guard let videoInfo = videoInfo, markedTimestamps.count >= AppConstants.minStepsPerRecipe else {
            error = .apiFailed(0, "请至少标记 \(AppConstants.minStepsPerRecipe) 个步骤")
            return
        }

        // 蜂窝网络确认
        guard await networkMonitor.confirmIfExpensive() else {
            error = .networkUnavailable
            return
        }

        flowState = .generating
        error = nil
        extractedImages = []
        stepDescriptions = []

        let spriteFrames = frameThumbnails.map { $0.image }
        let stream = await frameExtractionActor.extract(
            cid: videoInfo.cid,
            bv: videoInfo.bvid,
            timestamps: markedTimestamps,
            spriteFrames: spriteFrames
        )

        var heicURLs: [URL] = []

        for await event in stream {
            switch event {
            case .fetchingStream:
                extractionProgress = "正在获取视频流..."
            case .streamReady(let width, let height):
                extractionProgress = "视频流就绪 (\(width)×\(height))"
            case .parsingSidx:
                extractionProgress = "正在分析视频索引..."
            case .sidxParsed(_, let count):
                extractionProgress = "索引分析完成 (\(count) 段)"
            case .downloadingFrame(let current, let total):
                extractionProgress = "正在提取高清截图 \(current)/\(total)..."
            case .frameExtracted(let index):
                extractionProgress = "第 \(index) 帧提取完成"
            case .frameFailed(let index, _):
                extractionProgress = "第 \(index) 帧提取失败，已跳过"
            case .allComplete(let urls):
                heicURLs = urls
            case .degradedToSprite(let reason):
                extractionProgress = "已降级为预览图: \(reason)"
            }
        }

        // 加载 HEIC 为 UIImage
        for url in heicURLs {
            if let data = try? Data(contentsOf: url),
               let image = UIImage(data: data) {
                extractedImages.append(image)
            }
        }

        // VLM 生成步骤描述（可与帧提取流水线并行）
        if !extractedImages.isEmpty {
            do {
                stepDescriptions = try await vlmService.describeBatch(images: extractedImages)
            } catch {
                Logger.vlm.error("VLM 分析失败: \(error)")
                // VLM 失败不阻塞流程，步骤描述留空供用户手动填写
            }
        }

        flowState = .reviewing
    }

    /// 保存食谱
    func saveRecipe(title: String? = nil) async throws -> Recipe {
        guard let videoInfo = videoInfo else {
            throw AppError.apiFailed(0, "视频信息丢失")
        }

        // AC08: 再次检查重复
        if let existing = try await recipeRepo.findByBV(videoInfo.bvid) {
            throw AppError.duplicateRecipe(existing.title)
        }

        let recipe = Recipe(
            title: title ?? videoInfo.title,
            bvNumber: videoInfo.bvid,
            sourceURL: "https://www.bilibili.com/video/\(videoInfo.bvid)",
            sourceAuthor: videoInfo.authorName,
            cookTimeMinutes: nil,
            difficultyLevel: 2
        )

        // 创建 Step + StepImage
        for (index, image) in extractedImages.enumerated() {
            let desc = index < stepDescriptions.count ? stepDescriptions[index] : nil
            let timestamp = index < markedTimestamps.count ? markedTimestamps[index] : 0

            let step = Step(
                stepNumber: index + 1,
                descriptionText: desc?.descriptionText ?? "步骤 \(index + 1)",
                tipNote: desc?.tipNote,
                videoTimestampSeconds: timestamp
            )

            // 保存截图文件
            let docDir = FileManager.default
                .urls(for: .documentDirectory, in: .userDomainMask)[0]
            let imageDir = docDir.appendingPathComponent("Images")
            try FileManager.default.createDirectory(at: imageDir, withIntermediateDirectories: true)

            let imageFileName = "step_\(UUID().uuidString.prefix(12)).heic"
            let imageURL = imageDir.appendingPathComponent(imageFileName)
            if let heicData = image.heicData(compressionQuality: AppConstants.heicCompressionQuality) {
                try heicData.write(to: imageURL, options: .atomic)
            }

            // 生成缩略图
            let thumbName = "thumb_\(UUID().uuidString.prefix(12)).heic"
            let thumbURL = imageDir.appendingPathComponent(thumbName)
            let thumbnail = image.preparingThumbnail(of: CGSize(width: 300, height: 300))
            if let thumbData = thumbnail?.heicData(compressionQuality: 0.8) {
                try thumbData.write(to: thumbURL, options: .atomic)
            }

            let stepImage = StepImage(
                imagePath: imageURL.path,
                thumbnailPath: thumbURL.path,
                timestampSeconds: timestamp,
                orderIndex: index
            )
            step.images = [stepImage]
            recipe.steps.append(step)
        }

        try await recipeRepo.save(recipe)
        try await recipeRepo.consumeFreeSlot()

        flowState = .saved
        return recipe
    }

    /// 取消提取
    func cancelExtraction() {
        extractionTask?.cancel()
        extractionTask = nil
        flowState = .frameBrowsing
    }

    /// 重置
    func reset() {
        urlText = ""
        videoInfo = nil
        frameThumbnails = []
        markedTimestamps = []
        extractedImages = []
        stepDescriptions = []
        extractionProgress = ""
        error = nil
        flowState = .urlInput
    }
}
