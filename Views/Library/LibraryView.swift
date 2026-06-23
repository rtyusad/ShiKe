import SwiftUI

/// 食谱库首页
@MainActor
struct LibraryView: View {
    @State var vm: LibraryViewModel
    @Environment(\.appContainer) private var container

    var body: some View {
        Group {
            if vm.recipes.isEmpty && !vm.isLoading {
                EmptyLibraryView()
            } else {
                recipeGrid
            }
        }
        .navigationTitle("我的食谱")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(destination: ProfileView(vm: container.makeProfileVM())) {
                    Image(systemName: "person.circle")
                        .font(.title3)
                }
            }
        }
        .overlay {
            if vm.isLoading {
                LoadingOverlay()
            }
        }
        .task {
            await vm.load()
        }
        .refreshable {
            await vm.load()
        }
    }

    // MARK: - 食谱网格

    private var recipeGrid: some View {
        ScrollView {
            // 免费额度指示
            if !vm.isPremium {
                FreeSlotIndicator(
                    used: AppConstants.freeSlotLimit - vm.freeSlotsRemaining,
                    total: AppConstants.freeSlotLimit
                )
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16)
            ], spacing: 16) {
                ForEach(vm.recipes) { recipe in
                    NavigationLink(destination: RecipeDetailView(
                        vm: container.makeRecipeDetailVM(recipe: recipe)
                    )) {
                        RecipeCard(recipe: recipe, thumbnail: vm.thumbnailFor(recipe))
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            Task { await vm.deleteRecipe(recipe) }
                        } label: {
                            Label("删除食谱", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            // 底部升级入口
            if !vm.isPremium {
                upgradeBanner
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
            }

            Spacer(minLength: 100)
        }
        .background(Color.ricePaper)
    }

    // MARK: - 升级 Banner

    private var upgradeBanner: some View {
        NavigationLink(destination: UpgradeView(vm: container.makeUpgradeVM())) {
            HStack {
                Image(systemName: "diamond")
                    .font(.title3)
                Text("升级无限空间 仅需 ¥\(String(format: "%.0f", NSDecimalNumber(decimal: AppConstants.lifetimePrice).doubleValue))")
                    .font(.system(size: 15, weight: .medium))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
            }
            .padding()
            .background(
                LinearGradient(
                    colors: [.wokOrange.opacity(0.15), .ginger.opacity(0.1)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}

// MARK: - 颜色扩展

extension Color {
    static let ricePaper = Color(red: 0.984, green: 0.969, blue: 0.945)
    static let wokOrange = Color(red: 0.91, green: 0.416, blue: 0.239)
    static let soyBrown = Color(red: 0.176, green: 0.106, blue: 0.055)
    static let ginger = Color(red: 0.957, green: 0.773, blue: 0.259)
    static let scallionGreen = Color(red: 0.357, green: 0.549, blue: 0.306)
}
