import SwiftUI

/// 步骤确认页 — 展示提取的截图 + VLM 生成的文字，供用户确认后保存
@MainActor
struct StepReviewView: View {
    @Bindable var vm: AddRecipeViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var recipeTitle: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // 标题编辑
            VStack(alignment: .leading, spacing: 6) {
                Text("食谱标题")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("输入食谱标题", text: $recipeTitle)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.soyBrown)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .onAppear {
                recipeTitle = vm.videoInfo?.title ?? ""
            }

            Divider()

            // 步骤列表
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(Array(vm.extractedImages.enumerated()), id: \.offset) { index, image in
                        stepCard(index: index, image: image)
                    }
                }
                .padding(20)
            }

            // 保存按钮
            saveButton
        }
        .background(Color.ricePaper)
        .navigationTitle("确认步骤")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 步骤卡片

    private func stepCard(index: Int, image: UIImage) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // 步骤截图
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 100, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text("步骤 \(index + 1)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.wokOrange)

                if index < vm.stepDescriptions.count {
                    let desc = vm.stepDescriptions[index]
                    Text(desc.descriptionText.isEmpty ? "待描述" : desc.descriptionText)
                        .font(.system(size: 14))
                        .foregroundColor(.soyBrown)
                        .lineLimit(3)

                    if let tip = desc.tipNote, !tip.isEmpty {
                        Label(tip, systemImage: "lightbulb")
                            .font(.caption)
                            .foregroundColor(.ginger)
                    }
                } else {
                    Text("分析中...")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 保存按钮

    private var saveButton: some View {
        VStack(spacing: 8) {
            Button {
                Task {
                    do {
                        _ = try await vm.saveRecipe(title: recipeTitle)
                    } catch {
                        vm.setError(error as? AppError)
                    }
                }
            } label: {
                Text("💾 保存食谱")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.wokOrange)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 20)

            if let error = vm.error {
                Text(error.errorDescription ?? "")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.9))
    }
}
