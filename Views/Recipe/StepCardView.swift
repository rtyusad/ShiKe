import SwiftUI

/// 单张步骤卡片组件
/// 展示：高清截图 + 步骤标题 + 描述 + 小贴士 + 时长
struct StepCardView: View {
    let step: Step
    let image: UIImage?
    let currentIndex: Int
    let totalSteps: Int

    @State private var scale: CGFloat = 1.0

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // 步骤截图（带锅环装饰）
                ZStack(alignment: .topTrailing) {
                    WokRingFrame(size: nil) {
                        if let image = image {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity, maxHeight: 260)
                                .clipped()
                                .scaleEffect(scale)
                                .gesture(
                                    MagnificationGesture()
                                        .onChanged { value in scale = value }
                                        .onEnded { _ in
                                            withAnimation { scale = max(1.0, min(scale, 3.0)) }
                                        }
                                )
                                .gesture(
                                    MagnificationGesture()
                                        .onChanged { value in scale = value }
                                        .onEnded { _ in
                                            withAnimation { scale = max(1.0, min(scale, 3.0)) }
                                        }
                                )
                        } else {
                            Rectangle()
                                .fill(Color.gray.opacity(0.1))
                                .frame(height: 200)
                                .overlay {
                                    Image(systemName: "photo")
                                        .font(.largeTitle)
                                        .foregroundColor(.gray.opacity(0.3))
                                }
                        }
                    }

                    // 1080p 标签
                    if image != nil {
                        Text("1080p 高清")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.7))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .padding(8)
                    }
                }

                // 步骤详情
                VStack(alignment: .leading, spacing: 12) {
                    // 步骤标题
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(String(format: "%02d", currentIndex))
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(.wokOrange)
                        Text("步骤 \(step.stepNumber)")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.soyBrown)
                    }

                    // 描述
                    Text(step.descriptionText)
                        .font(.system(size: 16))
                        .foregroundColor(.soyBrown.opacity(0.8))
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)

                    // 小贴士
                    if let tip = step.tipNote, !tip.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Text("💡")
                                .font(.system(size: 14))
                            Text(tip)
                                .font(.system(size: 15))
                                .foregroundColor(.soyBrown.opacity(0.7))
                        }
                        .padding(12)
                        .background(Color.ginger.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    // 元数据行
                    HStack(spacing: 16) {
                        Label("视频 \(formatDuration(step.videoTimestampSeconds))", systemImage: "play.rectangle")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        Text("高清截图")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.6))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                .padding(20)
            }
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }
}
