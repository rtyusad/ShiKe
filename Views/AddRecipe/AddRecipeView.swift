import SwiftUI

/// 添加食谱页 — 粘贴链接入口
@MainActor
struct AddRecipeView: View {
    @State var vm: AddRecipeViewModel
    @Environment(\.appContainer) private var container

    var body: some View {
        Group {
            switch vm.flowState {
            case .urlInput, .fetching:
                urlInputView
            case .frameBrowsing:
                if let markerVM = vm.frameMarkerVM {
                    FrameBrowserView(
                        markerVM: markerVM,
                        addVM: vm
                    )
                }
            case .generating:
                generatingView
            case .reviewing:
                StepReviewView(vm: vm)
            case .saved:
                savedView
            }
        }
        .navigationTitle("添加食谱")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - URL 输入视图

    private var urlInputView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 标题区
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.wokOrange)
                    Text("从 B 站视频创建")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.soyBrown)
                    Text("粘贴链接，自动提取烹饪步骤帧")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 20)

                // 链接输入框
                URLInputField(text: Binding(
                    get: { vm.urlText },
                    set: { vm.updateURL($0) }
                ))

                // 格式提示
                HStack(spacing: 12) {
                    formatBadge("BV号链接")
                    formatBadge("b23.tv 短链接")
                }

                // 三步指引
                HStack(spacing: 0) {
                    stepGuide("①", "粘贴链接")
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    stepGuide("②", "标记步骤帧")
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    stepGuide("③", "生成食谱卡片")
                }
                .padding(.vertical, 8)

                // 获取视频按钮
                Button {
                    Task { await vm.fetchVideo() }
                } label: {
                    HStack {
                        if vm.flowState == .fetching {
                            ProgressView()
                                .tint(.white)
                            Text("获取中...")
                        } else {
                            Image(systemName: "play.rectangle")
                            Text("获取视频帧")
                        }
                    }
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        vm.urlText.isBilibiliURL
                            ? Color.wokOrange
                            : Color.gray.opacity(0.3)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(!vm.urlText.isBilibiliURL)
                .disabled(vm.flowState == .fetching)

                // 错误信息
                if let error = vm.error {
                    Text(error.errorDescription ?? "")
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }

                Divider()
                    .overlay { Text("或").font(.caption).foregroundColor(.secondary).padding(.horizontal, 8).background(Color.ricePaper) }

                // 手动创建入口（即将推出）
                Button {
                    // V1.1: 手动创建食谱（拍照+描述）
                } label: {
                    Label("手动创建食谱 · 即将推出", systemImage: "camera")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                }
                .disabled(true)

                // 底部技术说明
                Text("仅支持 bilibili.com 视频 · 不下载完整视频 · 仅提取关键帧截图")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.6))
                    .padding(.bottom, 40)
            }
            .padding(.horizontal, 24)
        }
        .background(Color.ricePaper)
    }

    // MARK: - 生成中

    private var generatingView: some View {
        VStack(spacing: 24) {
            Spacer()

            WokRingFrame(size: 120) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.wokOrange)
            }

            Text("正在提取高清步骤截图...")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.soyBrown)

            Text(vm.extractionProgress)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("取消") {
                vm.cancelExtraction()
            }
            .font(.system(size: 15))
            .foregroundColor(.secondary)
            .padding(.top, 12)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color.ricePaper)
    }

    // MARK: - 保存成功

    private var savedView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundColor(.scallionGreen)

            Text("食谱已保存！")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.soyBrown)

            Text("可以在「食谱库」中查看和跟做")
                .font(.system(size: 15))
                .foregroundColor(.secondary)

            Button {
                vm.reset()
            } label: {
                Text("继续添加")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.wokOrange)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color.ricePaper)
    }

    // MARK: - Helper

    private func formatBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.1))
            )
    }

    private func stepGuide(_ number: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(number)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.wokOrange)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(width: 70)
    }
}
