import SwiftUI

/// 横向滑动帧时间线组件
/// 展示雪碧图帧缩略图 + 时间戳 + 标记状态
struct FrameTimelineView: View {
    @Bindable var vm: FrameMarkerViewModel

    var body: some View {
        VStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 6) {
                    ForEach(Array(vm.frames.enumerated()), id: \.offset) { index, frame in
                        FrameThumbnail(
                            image: frame.image,
                            timestamp: frame.timestampSeconds,
                            isSelected: vm.selectedIndex == index,
                            isMarked: vm.isMarked(frame.timestampSeconds)
                        )
                        .onTapGesture {
                            vm.selectFrame(at: index)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }

            // 底部提示
            Text("浏览: \(vm.totalFrames) 帧 (10×10 雪碧图) · 点击标记 →")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.5))
                .padding(.horizontal, 20)
        }
    }
}
