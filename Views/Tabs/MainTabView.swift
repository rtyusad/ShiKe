import SwiftUI

/// 主 TabBar 容器
struct MainTabView: View {
    @State private var selectedTab: AppTab = .library
    @Environment(AppContainerKey.self) private var container

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                LibraryView(vm: container.makeLibraryVM())
            }
            .tabItem {
                Label(AppTab.library.title, systemImage: AppTab.library.icon)
            }
            .tag(AppTab.library)

            NavigationStack {
                AddRecipeView(vm: container.makeAddRecipeVM())
            }
            .tabItem {
                Label(AppTab.add.title, systemImage: AppTab.add.icon)
            }
            .tag(AppTab.add)

            NavigationStack {
                ProfileView(vm: container.makeProfileVM())
            }
            .tabItem {
                Label(AppTab.profile.title, systemImage: AppTab.profile.icon)
            }
            .tag(AppTab.profile)
        }
        .tint(.wokOrange)
    }
}

// MARK: - Tab 枚举

enum AppTab: Int, CaseIterable {
    case library
    case add
    case profile

    var title: String {
        switch self {
        case .library: "食谱库"
        case .add: "添加"
        case .profile: "我的"
        }
    }

    var icon: String {
        switch self {
        case .library: "books.vertical"
        case .add: "plus.circle.fill"
        case .profile: "person.circle"
        }
    }
}
