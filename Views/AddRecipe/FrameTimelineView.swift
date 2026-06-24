import SwiftUI

/// 横向滑动帧时间线组件
/// 展示雪碧图帧缩略图 + 时间戳 + 标记状态
struct FrameTimelineView: View {
    @Bindable var vm: FrameMarkerViewModel

    var body: some View {
        VStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(vm.frames) { frame in
                        FrameThumbnail(
                            image: frame.image,
                            timestamp: frame.timestampSeconds,
                            isSelected: vm.selectedFrame?.timestampSeconds == frame.timestampSeconds,
                            isMarked: vm.isMarked(frame.timestampSeconds)
                        )
                        .onTapGesture {
                            vm.selectFrame(timestamp: frame.timestampSeconds)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }

            // 底部提示
            HStack(spacing: 4) {
                Text("点击缩略图浏览 · 双击大图标记/取消 · 已选 \(vm.markedCount) 帧")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .padding(.horizontal, 20)
        }
    }
}
