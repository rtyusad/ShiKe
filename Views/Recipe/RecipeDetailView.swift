import SwiftUI

/// 食谱详情页 — 步骤卡片浏览
@MainActor
struct RecipeDetailView: View {
    @State var vm: RecipeDetailViewModel
    @Environment(\.appContainer) private var container
    @Environment(\.dismiss) private var dismiss

    @State private var showDeleteConfirm = false
    @State private var showStepList = false

    var body: some View {
        VStack(spacing: 0) {
            // 来源标注（AC07: 不可删除）
            SourceAttribution(
                author: vm.recipe.sourceAuthor,
                url: vm.recipe.sourceURL,
                bvNumber: vm.recipe.bvNumber
            )

            // 步骤进度
            StepProgressBar(current: vm.currentStepIndex + 1, total: vm.totalSteps)

            // 步骤卡片（可滑动）
            if let step = vm.currentStep {
                StepCardView(
                    step: step,
                    image: vm.imageForCurrentStep(),
                    currentIndex: vm.currentStepIndex + 1,
                    totalSteps: vm.totalSteps
                )
                .transition(.slide)
            }

            Spacer()

            // 底部导航
            stepNavigation
        }
        .background(Color.ricePaper)
        .navigationTitle(vm.recipe.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.secondary)
                }
            }
        }
        .alert("删除食谱", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                Task {
                    try? await vm.deleteRecipe()
                    dismiss()
                }
            }
        } message: {
            Text("确定要删除「\(vm.recipe.title)」吗？此操作不可撤销。")
        }
        .sheet(isPresented: $showStepList) {
            stepListView
        }
    }

    // MARK: - 步骤列表弹出页

    private var stepListView: some View {
        NavigationStack {
            List {
                ForEach(Array(vm.recipe.steps.enumerated()), id: \.offset) { index, step in
                    Button {
                        withAnimation { vm.goToStep(index) }
                        showStepList = false
                    } label: {
                        HStack(spacing: 12) {
                            Text("\(step.stepNumber)")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                                .frame(width: 28, height: 28)
                                .background(index == vm.currentStepIndex ? Color.wokOrange : Color.gray.opacity(0.4))
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(step.descriptionText)
                                    .font(.system(size: 15))
                                    .foregroundColor(.soyBrown)
                                    .lineLimit(2)
                                if let tip = step.tipNote, !tip.isEmpty {
                                    Text(tip)
                                        .font(.caption)
                                        .foregroundColor(.ginger)
                                }
                            }

                            Spacer()

                            if index == vm.currentStepIndex {
                                Image(systemName: "checkmark")
                                    .font(.caption)
                                    .foregroundColor(.wokOrange)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("全部步骤")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { showStepList = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - 步骤导航

    private var stepNavigation: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                Button {
                    withAnimation { vm.goToPreviousStep() }
                } label: {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("上一步")
                    }
                    .font(.system(size: 16))
                    .foregroundColor(vm.isFirstStep ? .gray.opacity(0.4) : .soyBrown)
                }
                .disabled(vm.isFirstStep)

                Spacer()

                Button {
                    withAnimation { vm.goToNextStep() }
                } label: {
                    HStack {
                        Text("下一步")
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(vm.isLastStep ? Color.scallionGreen : Color.wokOrange)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal, 20)

            // 全部步骤 + 开始跟做
            HStack(spacing: 20) {
                Button {
                    showStepList = true
                } label: {
                    Label("全部步骤(\(vm.totalSteps))", systemImage: "list.bullet")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }

                NavigationLink(destination: CookingView(
                    vm: container.makeCookingVM(recipe: vm.recipe)
                )) {
                    Label("开始跟做", systemImage: "frying.pan")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.wokOrange)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.wokOrange, lineWidth: 1.5)
                        )
                }
            }
            .padding(.bottom, 8)
        }
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.9))
    }
}
