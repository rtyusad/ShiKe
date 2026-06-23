import SwiftUI

/// 全屏跟做模式 — "夜间厨房"沉浸式界面
struct CookingView: View {
    @State var vm: CookingViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            // 深色厨房背景
            Color.soyBrown.ignoresSafeArea()

            if vm.isCompleted {
                completedView
            } else if let step = vm.currentStep {
                cookingContent(step: step)
            }
        }
        .navigationBarHidden(true)
        .statusBarHidden(true)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true  // 保持屏幕常亮
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    // MARK: - 烹饪内容

    private func cookingContent(step: Step) -> some View {
        VStack(spacing: 0) {
            // 步骤计数器
            Text("🍳 \(vm.currentStepIndex + 1) / \(vm.totalSteps)")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.wokOrange)
                .padding(.top, 56)
                .padding(.bottom, 16)

            // 步骤截图
            if let imageData = try? Data(contentsOf: URL(fileURLWithPath: step.images.first?.imagePath ?? "")),
               let uiImage = UIImage(data: imageData) {
                WokRingFrame(size: nil) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
                .padding(.horizontal, 20)
            }

            Spacer()

            // 步骤标题 + 描述
            VStack(spacing: 12) {
                Text(step.descriptionText.components(separatedBy: "：").first ?? step.descriptionText)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)

                Text(step.descriptionText)
                    .font(.system(size: 18))
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .padding(.horizontal, 24)
            }

            Divider()
                .background(Color.white.opacity(0.2))
                .padding(.vertical, 16)

            // 导航按钮（大按钮，适合湿手操作）
            HStack(spacing: 40) {
                Button {
                    vm.goToPreviousStep()
                } label: {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("上一步")
                    }
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(minWidth: 120, minHeight: 56)
                }
                .disabled(vm.currentStepIndex == 0)

                Button {
                    vm.goToNextStep()
                } label: {
                    HStack {
                        Text(vm.currentStepIndex == vm.totalSteps - 1 ? "完成" : "下一步")
                        Image(systemName: vm.currentStepIndex == vm.totalSteps - 1 ? "checkmark" : "chevron.right")
                    }
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .frame(minWidth: 140, minHeight: 56)
                    .background(
                        vm.currentStepIndex == vm.totalSteps - 1
                            ? Color.scallionGreen
                            : Color.wokOrange
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 28))
                }
            }
            .padding(.horizontal, 20)

            // 底部工具栏
            HStack(spacing: 32) {
                // 计时器
                Button {
                    vm.toggleTimer()
                } label: {
                    Label(
                        formatDuration(vm.elapsedSeconds),
                        systemImage: vm.isTimerRunning ? "clock.fill" : "clock"
                    )
                    .font(.system(size: 16))
                    .foregroundColor(vm.isTimerRunning ? .wokOrange : .white.opacity(0.6))
                }

                // 语音开关
                Button {
                    vm.toggleVoice()
                } label: {
                    Label("语音", systemImage: vm.isVoiceEnabled ? "speaker.wave.2.fill" : "speaker.slash")
                        .font(.system(size: 16))
                        .foregroundColor(vm.isVoiceEnabled ? .white : .white.opacity(0.4))
                }

                // 退出
                Button {
                    dismiss()
                } label: {
                    Label("退出", systemImage: "xmark.circle")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .padding(.vertical, 20)
            .padding(.bottom, 32)
        }
    }

    // MARK: - 完成视图

    private var completedView: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("🎉")
                .font(.system(size: 72))

            Text("烹饪完成！")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)

            Text("又学会了一道菜 👏")
                .font(.system(size: 18))
                .foregroundColor(.white.opacity(0.7))

            Button {
                dismiss()
            } label: {
                Text("返回食谱")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(Color.wokOrange)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            Spacer()
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
