import SwiftUI
import Observation
import OSLog
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

    /// 允许子 View 回退状态（如从确认页返回帧浏览页）
    func setFlowState(_ state: FlowState) {
        flowState = state
    }
    private(set) var urlText: String = ""
    private(set) var error: AppError?

    // 视频信息
    private(set) var videoInfo: BiliInfoAPI.VideoInfo?
    private(set) var frameThumbnails: [SpriteSheetParser.FrameThumbnail] = []
    private(set) var markedTimestamps: [Int] = []

    // 高清提取进度
    private(set) var extractionProgress: String = ""
    private(set) var extractedImages: [UIImage] = []
    private(set) var extractedImageURLs: [URL] = []  // Actor 产出的 HEIC 原始路径
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

    /// 设置错误状态（供外部 View 调用）
    func setError(_ newError: AppError?) {
        error = newError
    }

    /// 同步 FrameMarker 已标记的时间戳
    func syncMarkedTimestamps(_ timestamps: [Int]) {
        markedTimestamps = timestamps.sorted()
    }

    /// 生成步骤卡片（阶段二：sidx+GOP 高清提取 + VLM）
    func generateSteps() async {
        guard let videoInfo = videoInfo, markedTimestamps.count >= AppConstants.minStepsPerRecipe else {
            error = .apiFailed(0, "请至少标记 \(AppConstants.minStepsPerRecipe) 个步骤")
            return
        }

        // 网络确认
        guard networkMonitor.confirmIfExpensive() else {
            error = .networkUnavailable
            return
        }

        flowState = .generating
        error = nil
        extractedImages = []
        extractedImageURLs = []
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

        // 记录 HEIC URL + 加载为 UIImage
        extractedImageURLs = heicURLs
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

    /// 删除指定步骤
    func removeStep(at index: Int) {
        guard extractedImages.indices.contains(index) else { return }
        extractedImages.remove(at: index)
        if extractedImageURLs.indices.contains(index) { extractedImageURLs.remove(at: index) }
        if stepDescriptions.indices.contains(index) { stepDescriptions.remove(at: index) }
        if markedTimestamps.indices.contains(index) { markedTimestamps.remove(at: index) }
    }

    /// 拖动排序步骤（同步所有并行数组）
    func moveSteps(from source: IndexSet, to destination: Int) {
        extractedImages.move(fromOffsets: source, toOffset: destination)
        extractedImageURLs.move(fromOffsets: source, toOffset: destination)
        stepDescriptions.move(fromOffsets: source, toOffset: destination)
        markedTimestamps.move(fromOffsets: source, toOffset: destination)
    }

    /// 更新单个步骤描述（供 StepReviewView 编辑回写）
    func updateStepDescription(at index: Int, description: String, tip: String?) {
        guard stepDescriptions.indices.contains(index) else { return }
        stepDescriptions[index] = StepDescription(
            descriptionText: description,
            tipNote: tip
        )
    }

    /// 保存食谱
    func saveRecipe(title: String? = nil, coverImageIndex: Int? = nil) async throws {
        guard let videoInfo = videoInfo else {
            throw AppError.apiFailed(0, "视频信息丢失")
        }

        let finalTitle: String = {
            if let t = title, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return t
            }
            return videoInfo.title
        }()

        let docDir = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
        let imageDir = docDir.appendingPathComponent("Images")
        try FileManager.default.createDirectory(at: imageDir, withIntermediateDirectories: true)

        let count = extractedImages.count
        let urlCount = extractedImageURLs.count
        var stepDataList: [RecipeSaveData.StepData] = []

        // 准备图片文件 + 构建 StepData（所有 Model 无关工作在 MainActor 完成）
        for index in 0..<count {
            let desc = index < stepDescriptions.count ? stepDescriptions[index] : nil
            let timestamp = index < markedTimestamps.count ? markedTimestamps[index] : 0
            let image = extractedImages[index]

            let imagePath: String
            if index < urlCount {
                let sourceURL = extractedImageURLs[index]
                let destURL = imageDir.appendingPathComponent(sourceURL.lastPathComponent)
                if sourceURL.path != destURL.path {
                    try? FileManager.default.removeItem(at: destURL)
                    do {
                        try FileManager.default.copyItem(at: sourceURL, to: destURL)
                        imagePath = destURL.path
                    } catch {
                        Logger.recipe.warning("HEIC 复制失败 \(error), 降级为重新编码")
                        imagePath = try encodeImageToHEIC(image, dir: imageDir)
                    }
                } else {
                    imagePath = sourceURL.path
                }
            } else {
                imagePath = try encodeImageToHEIC(image, dir: imageDir)
            }

            let thumbName = "thumb_\(UUID().uuidString.prefix(12)).heic"
            let thumbURL = imageDir.appendingPathComponent(thumbName)
            let thumbnail = image.preparingThumbnail(of: CGSize(width: 300, height: 300))
            if let thumbData = thumbnail?.heicData(compressionQuality: 0.8) {
                try? thumbData.write(to: thumbURL, options: .atomic)
            }

            stepDataList.append(RecipeSaveData.StepData(
                stepNumber: index + 1,
                descriptionText: desc?.descriptionText ?? "步骤 \(index + 1)",
                tipNote: desc?.tipNote,
                videoTimestampSeconds: timestamp,
                imagePath: imagePath,
                thumbnailPath: thumbURL.path,
                orderIndex: index
            ))
        }

        // ✅ 传递 Sendable 数据传输对象，不跨越 Actor 传递 @Model
        // 封面图路径
        let coverPath: String? = {
            if let ci = coverImageIndex, ci < stepDataList.count {
                return stepDataList[ci].imagePath
            }
            return stepDataList.first?.imagePath
        }()

        let saveData = RecipeSaveData(
            title: finalTitle,
            bvNumber: videoInfo.bvid,
            sourceURL: "https://www.bilibili.com/video/\(videoInfo.bvid)",
            sourceAuthor: videoInfo.authorName,
            cookTimeMinutes: nil,
            difficultyLevel: 2,
            coverImagePath: coverPath,
            steps: stepDataList
        )

        try await recipeRepo.saveAndConsumeSlot(with: saveData)

        flowState = .saved
    }

    /// HEIC 编码保存（带唯一文件名）
    private func encodeImageToHEIC(_ image: UIImage, dir: URL) throws -> String {
        let fileName = "step_\(UUID().uuidString.prefix(12)).heic"
        let fileURL = dir.appendingPathComponent(fileName)
        guard let heicData = image.heicData(compressionQuality: AppConstants.heicCompressionQuality) else {
            throw AppError.apiFailed(0, "图片编码失败")
        }
        try heicData.write(to: fileURL, options: .atomic)
        return fileURL.path
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
