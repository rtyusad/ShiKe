import SwiftUI
import Observation

/// 帧浏览标记 ViewModel
/// 管理雪碧图帧时间线的交互状态
@MainActor
@Observable
final class FrameMarkerViewModel {
    let frames: [SpriteSheetParser.FrameThumbnail]
    let videoTitle: String
    let videoAuthor: String
    let bvNumber: String
    let durationSeconds: Int

    private(set) var selectedIndex: Int = 0
    private(set) var markedTimestamps: Set<Int> = []

    var selectedFrame: SpriteSheetParser.FrameThumbnail? {
        guard selectedIndex < frames.count else { return nil }
        return frames[selectedIndex]
    }

    var markedCount: Int { markedTimestamps.count }
    var totalFrames: Int { frames.count }

    init(
        frames: [SpriteSheetParser.FrameThumbnail],
        videoTitle: String,
        videoAuthor: String,
        bvNumber: String,
        durationSeconds: Int
    ) {
        self.frames = frames
        self.videoTitle = videoTitle
        self.videoAuthor = videoAuthor
        self.bvNumber = bvNumber
        self.durationSeconds = durationSeconds
    }

    // MARK: - 输入

    func selectFrame(at index: Int) {
        guard index >= 0, index < frames.count else { return }
        selectedIndex = index
    }

    /// 按时间戳选择帧
    func selectFrame(timestamp: Int) {
        guard let index = frames.firstIndex(where: { $0.timestampSeconds == timestamp }) else { return }
        selectedIndex = index
    }

    func toggleMarkCurrent() {
        guard let frame = selectedFrame else { return }
        if markedTimestamps.contains(frame.timestampSeconds) {
            markedTimestamps.remove(frame.timestampSeconds)
        } else {
            markedTimestamps.insert(frame.timestampSeconds)
        }
    }

    func isMarked(_ timestamp: Int) -> Bool {
        markedTimestamps.contains(timestamp)
    }

    /// 获取已标记的时间戳列表（按时间排序）
    func sortedMarkedTimestamps() -> [Int] {
        markedTimestamps.sorted()
    }

    /// 是否可以生成（至少标记 minSteps 个步骤）
    var canGenerate: Bool {
        markedTimestamps.count >= AppConstants.minStepsPerRecipe
    }
}
