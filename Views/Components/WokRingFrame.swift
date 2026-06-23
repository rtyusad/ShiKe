import SwiftUI

/// "锅环"渐变圆环装饰 — 食刻 App 的视觉签名元素
/// 在步骤图片周围绘制灶火橙→姜黄的渐变圆环
struct WokRingFrame<Content: View>: View {
    let size: CGFloat?
    @ViewBuilder let content: () -> Content

    init(size: CGFloat? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.size = size
        self.content = content
    }

    var body: some View {
        content()
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        LinearGradient(
                            colors: [
                                .wokOrange.opacity(0.6),
                                .ginger.opacity(0.3),
                                .wokOrange.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 3
                    )
            )
            .shadow(
                color: .wokOrange.opacity(0.12),
                radius: 8, x: 0, y: 2
            )
    }
}
