import SwiftUI

/// 食谱卡片组件（2 列网格中的单个卡片）
struct RecipeCard: View {
    let recipe: Recipe
    let thumbnail: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 封面图
            Group {
                if let thumbnail = thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(16/10, contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.15))
                        .aspectRatio(16/10, contentMode: .fit)
                        .overlay {
                            Image(systemName: "photo")
                                .font(.title2)
                                .foregroundColor(.gray.opacity(0.4))
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // 标题
            Text(recipe.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.soyBrown)
                .lineLimit(2)

            // 底部信息
            HStack(spacing: 4) {
                if let cookTime = recipe.cookTimeMinutes {
                    Label("\(cookTime)min", systemImage: "clock")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // 难度星星
                Text(String(repeating: "⭐", count: recipe.difficultyLevel))
                    .font(.caption2)
            }
        }
        .padding(8)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }
}
