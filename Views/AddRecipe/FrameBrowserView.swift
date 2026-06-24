import SwiftUI

/// 帧浏览标记页 — 阶段一核心 UI
/// 展示雪碧图帧时间线，供用户滑动浏览并标记关键步骤节点
@MainActor
struct FrameBrowserView: View {
    let markerVM: FrameMarkerViewModel
    let addVM: AddRecipeViewModel

    /// 双击放大图标记/取消标记
    @State private var showMarkHint = false

    var body: some View {
        VStack(spacing: 0) {
            // 视频信息栏
            videoInfoBar

            // 大图预览区 + 双击标记
            largePreview

            // 时间线
            FrameTimelineView(vm: markerVM)
                .frame(height: 120)

            // 底部操作
            bottomActions
        }
        .background(Color.ricePaper)
        .navigationTitle("标记步骤帧")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text("已选: \(markerVM.markedCount)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(markerVM.markedCount > 0 ? .scallionGreen : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(markerVM.markedCount > 0
                                ? Color.scallionGreen.opacity(0.1)
                                : Color.gray.opacity(0.08))
                    )
            }
        }
    }

    // MARK: - 视频信息栏

    private var videoInfoBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "play.rectangle")
                .font(.title3)
                .foregroundColor(.wokOrange)

            VStack(alignment: .leading, spacing: 2) {
                Text(markerVM.videoTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.soyBrown)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text("@\(markerVM.videoAuthor)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(markerVM.bvNumber)
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.6))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            Spacer()

            Text(formatDuration(markerVM.durationSeconds))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.8))
    }

    // MARK: - 大图预览

    private var largePreview: some View {
        VStack(spacing: 8) {
            if let frame = markerVM.selectedFrame {
                let isMarked = markerVM.isMarked(frame.timestampSeconds)

                ZStack {
                    WokRingFrame(size: nil) {
                        Image(uiImage: frame.image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    }
                    .id(frame.id)        // 强制按帧 ID 重建视图，避免 SwiftUI 复用残留
                    .clipped()            // 裁切溢出内容
                    // 双击标记
                    .onTapGesture(count: 2) {
                        markerVM.toggleMarkCurrent()
                        // 闪烁提示
                        withAnimation(.easeInOut(duration: 0.15)) { showMarkHint = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            withAnimation { showMarkHint = false }
                        }
                    }

                    // 标记状态指示器
                    VStack(spacing: 4) {
                        if showMarkHint || isMarked {
                            Image(systemName: isMarked ? "checkmark.diamond.fill" : "diamond")
                                .font(.system(size: 36))
                                .foregroundColor(isMarked ? .scallionGreen : .white.opacity(0.7))
                                .shadow(radius: 4)
                                .transition(.scale.combined(with: .opacity))
                        }

                        Text(formatDuration(frame.timestampSeconds))
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(8)
                }

                // 提示文字
                Text(isMarked ? "✅ 已标记为步骤帧 · 双击取消" : "👆 双击大图标记为步骤帧")
                    .font(.system(size: 12))
                    .foregroundColor(isMarked ? .scallionGreen : .secondary.opacity(0.7))
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.1))
                    .overlay {
                        Text("点击时间线选择一帧查看大图")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    // MARK: - 底部操作

    private var bottomActions: some View {
        HStack(spacing: 16) {
            // 取消 → 返回 URL 输入页 (P1-1 修复)
            Button {
                addVM.reset()
            } label: {
                Text("取消")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                let timestamps = markerVM.sortedMarkedTimestamps()
                addVM.syncMarkedTimestamps(timestamps)
                Task { await addVM.generateSteps() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                    Text("生成步骤卡片 (\(markerVM.markedCount)帧)")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    markerVM.canGenerate
                        ? Color.wokOrange
                        : Color.gray.opacity(0.4)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(!markerVM.canGenerate)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.9))
    }

    // MARK: - Helper

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
