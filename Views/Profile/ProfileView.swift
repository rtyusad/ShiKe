import SwiftUI

/// 个人中心页
@MainActor
struct ProfileView: View {
    @State var vm: ProfileViewModel
    @Environment(\.appContainer) private var container
    @State private var isEditingNickname = false
    @State private var editedNickname = ""

    var body: some View {
        List {
            // 用户信息卡片
            Section {
                HStack(spacing: 16) {
                    // 头像
                    ZStack {
                        Circle()
                            .fill(Color.wokOrange.opacity(0.15))
                            .frame(width: 64, height: 64)
                        Image(systemName: "person.fill")
                            .font(.title)
                            .foregroundColor(.wokOrange)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "camera.circle.fill")
                            .font(.title3)
                            .foregroundColor(.wokOrange)
                            .background(Circle().fill(Color.white).frame(width: 20, height: 20))
                            .offset(x: 4, y: 4)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        if isEditingNickname {
                            TextField("昵称", text: $editedNickname)
                                .font(.system(size: 18, weight: .semibold))
                                .onSubmit {
                                    Task { await vm.updateNickname(editedNickname) }
                                    isEditingNickname = false
                                }
                        } else {
                            HStack(spacing: 6) {
                                Text(vm.nickname.isEmpty ? "设置昵称" : vm.nickname)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.soyBrown)
                                Button {
                                    editedNickname = vm.nickname
                                    isEditingNickname = true
                                } label: {
                                    Image(systemName: "pencil")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            // 统计数据
            Section {
                HStack {
                    statItem("已保存食谱", "\(vm.totalRecipes)")
                    Divider()
                    statItem("跟做完成", "\(vm.totalCookCount)")
                }
                .padding(.vertical, 4)

                if !vm.isPremium {
                    VStack(spacing: 8) {
                        HStack {
                            Text("免费额度")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(vm.freeSlotsUsed) / \(vm.freeSlotsLimit)")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.soyBrown)
                        }
                        ProgressView(value: Double(vm.freeSlotsUsed), total: Double(vm.freeSlotsLimit))
                            .tint(.wokOrange)
                    }
                }
            }

            // 升级入口
            if !vm.isPremium {
                Section {
                    NavigationLink(destination: UpgradeView(vm: container.makeUpgradeVM())) {
                        HStack {
                            Image(systemName: "diamond.fill")
                                .foregroundColor(.ginger)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("💎 升级无限空间")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.soyBrown)
                                Text("¥\(String(format: "%.0f", NSDecimalNumber(decimal: AppConstants.lifetimePrice).doubleValue)) 终身买断 — 一次付费，永久使用")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            } else {
                Section {
                    HStack {
                        Image(systemName: "diamond.fill")
                            .foregroundColor(.ginger)
                        Text("终身版用户")
                            .font(.system(size: 15))
                            .foregroundColor(.soyBrown)
                        Spacer()
                        Text("无限食谱")
                            .font(.caption)
                            .foregroundColor(.scallionGreen)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.scallionGreen.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }

            // 法律文本
            Section {
                NavigationLink("关于 食刻 v1.0") {
                    Text("食刻 — B站美食视频 → 步骤卡片\n\n将 B 站美食创作者视频转化为结构化步骤卡片 + 关键帧截图\n\n版本: 1.0 (MVP)")
                        .padding()
                }
                NavigationLink("用户协议") {
                    ScrollView { Text(legalTexts.userAgreement).padding() }
                }
                NavigationLink("隐私政策") {
                    ScrollView { Text(legalTexts.privacyPolicy).padding() }
                }
                NavigationLink("版权声明") {
                    ScrollView { Text(legalTexts.copyright).padding() }
                }
            }
        }
        .navigationTitle("个人中心")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
    }

    // MARK: - Helper

    private func statItem(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.wokOrange)
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 法律文本（占位，正式上线前由法务审核）

private struct legalTexts {
    static let userAgreement = """
    用户协议

    1. "食刻"是一款个人烹饪学习辅助工具。用户通过本 App 提取的视频截图和文字描述仅供个人学习、研究、欣赏之用。

    2. 所有提取内容的著作权及相关权利均归原作者（B 站 UP 主）所有。

    3. 用户承诺不将提取内容用于任何商业目的或公开传播。

    4. 权利人可通过侵权投诉通道进行投诉，我们将在 5 个工作日内处理。
    """

    static let privacyPolicy = """
    隐私政策

    1. 所有数据存储在您的设备本地，不会上传至任何服务器。

    2. 本 App 不收集任何个人信息、不追踪用户行为。

    3. 网络请求仅用于获取 B 站公开 API 数据（视频信息、预览图）。

    4. 付费通过 Apple StoreKit 2 处理，支付信息由 Apple 管理，本 App 不获取。
    """

    static let copyright = """
    版权声明

    1. "食刻" App 本身代码和设计元素的版权归开发者所有。

    2. 通过本 App 提取的视频截图、文字描述等内容的版权归原 B 站 UP 主所有。

    3. 用户在"食刻"中保存的内容仅供个人学习使用。

    4. 如您是权利人且发现侵权内容，请联系我们，将在 5 个工作日内处理。

    侵权投诉邮箱：待定
    """
}
