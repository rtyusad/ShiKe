import UIKit
import Foundation
import OSLog
/// 帧提取管线 actor
///
/// 执行策略（v1.1 优化）：
/// - sidx 解析阶段串行（轻量级网络请求 ~6KB，无法并行）
/// - 帧提取阶段并行（withTaskGroup，maxConcurrent=3）
/// - 每帧有独立的临时文件，无并发冲突
/// - 降级链路：sidx 失败 → 雪碧图；单帧失败 → 跳过继续
///
/// 进度报告：通过 AsyncStream 逐帧报告事件
actor FrameExtractionActor {

    // MARK: - 依赖
    private let playURLAPI: BiliPlayURLAPI
    private let downloader: GOPDownloader
    private let sidxParser: SidxBoxParser
    private let assembler: MP4Assembler
    private let extractor: IFrameExtractor
    private let cleanup: FileCleanup

    // MARK: - 进度事件

    enum ExtractionEvent {
        case fetchingStream
        case streamReady(width: Int, height: Int)
        case parsingSidx
        case sidxParsed(version: UInt8, entryCount: Int)
        case downloadingFrame(Int, of: Int)
        case frameExtracted(Int)
        case frameFailed(Int, Error)
        case allComplete([URL])
        case degradedToSprite(String)
    }

    init(
        playURLAPI: BiliPlayURLAPI,
        downloader: GOPDownloader,
        sidxParser: SidxBoxParser,
        assembler: MP4Assembler,
        extractor: IFrameExtractor,
        cleanup: FileCleanup
    ) {
        self.playURLAPI = playURLAPI
        self.downloader = downloader
        self.sidxParser = sidxParser
        self.assembler = assembler
        self.extractor = extractor
        self.cleanup = cleanup
    }

    // MARK: - 主入口

    /// 对给定的时间戳列表提取高清 I 帧
    func extract(
        cid: Int,
        bv: String,
        timestamps: [Int],
        spriteFrames: [UIImage],
        maxConcurrent: Int = 3
    ) -> AsyncStream<ExtractionEvent> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    let urls = try await performExtraction(
                        cid: cid, bv: bv,
                        timestamps: timestamps,
                        spriteFrames: spriteFrames,
                        maxConcurrent: maxConcurrent,
                        onEvent: { continuation.yield($0) }
                    )
                    continuation.yield(.allComplete(urls))
                } catch {
                    Logger.frameExtraction.error("管线失败: \(error)")
                    // 降级为雪碧图
                    continuation.yield(.degradedToSprite(error.localizedDescription))
                    let spriteURLs = try? await saveSpriteFrames(spriteFrames, for: timestamps)
                    continuation.yield(.allComplete(spriteURLs ?? []))
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - 管线执行

    private func performExtraction(
        cid: Int,
        bv: String,
        timestamps: [Int],
        spriteFrames: [UIImage],
        maxConcurrent: Int,
        onEvent: @escaping (ExtractionEvent) -> Void
    ) async throws -> [URL] {
        guard !timestamps.isEmpty else { return [] }

        // ═══ 阶段一：获取视频流 + sidx 解析（串行） ═══

        onEvent(.fetchingStream)
        let segmentBase = try await fetchPlayURLWithRetry(cid: cid, bvid: bv)
        onEvent(.streamReady(width: segmentBase.width, height: segmentBase.height))

        onEvent(.parsingSidx)
        let (initData, sidxData) = try await downloader.downloadInitAndSidx(
            baseURL: segmentBase.baseURL,
            initRange: segmentBase.initializationRange,
            indexRange: segmentBase.indexRange
        )
        let sidxResult = try sidxParser.parse(sidxData)
        onEvent(.sidxParsed(version: sidxResult.version, entryCount: sidxResult.entries.count))

        // ═══ 阶段二：并行提取各帧（withTaskGroup, system-managed concurrency） ═══

        let totalCount = timestamps.count
        let docDir = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Images")
        try FileManager.default.createDirectory(at: docDir, withIntermediateDirectories: true)

        let results = try await withThrowingTaskGroup(
            of: (Int, URL)?.self
        ) { [self] group in
            // 添加所有任务，TaskGroup 自动管理并发数
            for (index, timestamp) in timestamps.enumerated() {
                group.addTask { [self] in
                    onEvent(.downloadingFrame(index + 1, of: totalCount))

                    do {
                        let url = try await self.processSingleFrame(
                            index: index,
                            timestamp: timestamp,
                            initData: initData,
                            baseURL: segmentBase.baseURL,
                            sidxResult: sidxResult,
                            outputDir: docDir
                        )
                        onEvent(.frameExtracted(index + 1))
                        return (index, url)
                    } catch {
                        Logger.frameExtraction.error("帧 \(index + 1) 提取失败: \(error)")
                        onEvent(.frameFailed(index + 1, error))
                        return nil  // 跳过失败的帧
                    }
                }
            }

            // 收集结果
            var urls = [(Int, URL)]()
            for try await result in group {
                if let (index, url) = result {
                    urls.append((index, url))
                }
            }
            return urls.sorted { $0.0 < $1.0 }.map { $0.1 }
        }

        Logger.frameExtraction.info("高清提取完成: \(results.count)/\(totalCount) 帧")
        return results
    }

    // MARK: - 单帧处理

    private func processSingleFrame(
        index: Int,
        timestamp: Int,
        initData: Data,
        baseURL: String,
        sidxResult: SidxBoxParser.ParseResult,
        outputDir: URL
    ) async throws -> URL {
        // 1. 二分查找对应的 subsegment
        guard let entry = sidxResult.findSubsegmentWithRetry(for: Double(timestamp)) else {
            throw AppError.sidxParseFailed("无法定位时间戳 \(timestamp)s")
        }

        // 2. Range 下载该 subsegment
        let subsegmentData = try await downloader.downloadSubsegment(
            baseURL: baseURL,
            byteOffset: entry.byteOffset,
            byteLength: entry.byteLength
        )

        // 3. 拼装 mini-mp4
        let tempURL = try assembler.assemble(
            initData: initData,
            subsegmentData: subsegmentData,
            index: index
        )

        // 4. 提取 I 帧
        let image = try await extractor.extract(from: tempURL, at: 0)

        // 5. HEIC 编码 + 保存
        guard let heicData = image.heicData(compressionQuality: AppConstants.heicCompressionQuality) else {
            throw AppError.iframeExtractionFailed
        }

        let fileName = "step_\(UUID().uuidString.prefix(12)).heic"
        let fileURL = outputDir.appendingPathComponent(fileName)
        try heicData.write(to: fileURL, options: .atomic)

        // 6. 清理临时 mp4（AC05）
        cleanup.deleteFile(at: tempURL)

        return fileURL
    }

    // MARK: - 降级：保存雪碧图帧

    private func saveSpriteFrames(_ frames: [UIImage], for timestamps: [Int]) async throws -> [URL] {
        let docDir = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Images")
        try FileManager.default.createDirectory(at: docDir, withIntermediateDirectories: true)

        var urls: [URL] = []
        for (index, frame) in frames.enumerated() {
            guard index < timestamps.count else { break }
            guard let heicData = frame.heicData(compressionQuality: AppConstants.heicCompressionQuality) else {
                continue
            }
            let fileName = "sprite_step_\(UUID().uuidString.prefix(12)).heic"
            let fileURL = docDir.appendingPathComponent(fileName)
            try heicData.write(to: fileURL, options: .atomic)
            urls.append(fileURL)
        }
        return urls
    }

    // MARK: - 带重试的 playurl 获取

    /// 获取 playurl，支持 WBI key 过期自动重试
    private func fetchPlayURLWithRetry(
        cid: Int, bvid: String, maxRetries: Int = 2
    ) async throws -> BiliPlayURLAPI.SegmentBase {
        do {
            return try await playURLAPI.fetch(cid: cid, bvid: bvid)
        } catch AppError.wbiKeyExpired {
            Logger.frameExtraction.warning("WBI key 过期, 自动重试 (\(maxRetries)次剩余)")
            guard maxRetries > 0 else { throw AppError.wbiSignFailed }
            return try await fetchPlayURLWithRetry(cid: cid, bvid: bvid, maxRetries: maxRetries - 1)
        }
    }
}
