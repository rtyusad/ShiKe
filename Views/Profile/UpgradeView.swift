import SwiftUI

/// 付费升级页 — ¥8 终身买断
struct UpgradeView: View {
    @State var vm: UpgradeViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // 顶部渐变区
                VStack(spacing: 16) {
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 56))
                        .foregroundColor(.ginger)
                        .padding(.top, 32)

                    Text("解锁无限食谱空间")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.soyBrown)

                    Text("一次购买，终身使用")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }

                // 价格对比
                HStack(spacing: 16) {
                    priceCard(
                        title: "免费版",
                        space: "3 个食谱",
                        price: "¥0",
                        recommended: false
                    )
                    priceCard(
                        title: "终身版",
                        space: "无限食谱",
                        price: "¥\(String(format: "%.0f", NSDecimalNumber(decimal: AppConstants.lifetimePrice).doubleValue))",
                        recommended: true
                    )
                }
                .padding(.horizontal, 20)

                // 权益清单
                VStack(spacing: 16) {
                    benefitRow("♾️", "无限食谱存储空间")
                    benefitRow("✅", "永久使用，无需续费")
                    benefitRow("🆕", "未来所有功能更新")
                    benefitRow("🔒", "数据本地存储，隐私安全")
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 32)

                // 购买按钮
                VStack(spacing: 16) {
                    Button {
                        Task { await vm.purchase() }
                    } label: {
                        HStack {
                            if vm.isPurchasing {
                                ProgressView().tint(.white)
                            }
                            Text("¥\(String(format: "%.0f", NSDecimalNumber(decimal: AppConstants.lifetimePrice).doubleValue)) 立即解锁")
                                .font(.system(size: 18, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(vm.isPurchasing ? Color.gray : Color.wokOrange)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .disabled(vm.isPurchasing)

                    // 竞品对比
                    Text("对比：下厨房 ¥228/年 | 香哈菜谱 ¥12/月")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.7))

                    // 恢复购买
                    Button {
                        Task { await vm.restorePurchases() }
                    } label: {
                        Text("恢复购买")
                            .font(.system(size: 14))
                            .foregroundColor(.wokOrange)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)

                // 错误/成功提示
                if let error = vm.error {
                    Text(error.errorDescription ?? "")
                        .font(.caption)
                        .foregroundColor(.red)
                }

                if vm.purchaseSuccess {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.scallionGreen)
                        Text("购买成功！无限食谱已解锁")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.scallionGreen)
                    }
                    .padding(.bottom, 20)
                }
            }
        }
        .background(Color.ricePaper)
        .navigationTitle("升级")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: vm.purchaseSuccess) { _, success in
            if success {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    dismiss()
                }
            }
        }
    }

    // MARK: - 价格卡片

    private func priceCard(title: String, space: String, price: String, recommended: Bool) -> some View {
        VStack(spacing: 12) {
            if recommended {
                Text("推荐")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Color.ginger)
                    .clipShape(Capsule())
            }

            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.soyBrown)

            Text(space)
                .font(.system(size: 13))
                .foregroundColor(.secondary)

            Text(price)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(recommended ? .wokOrange : .secondary)
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            recommended ? Color.ginger : Color.gray.opacity(0.2),
                            lineWidth: recommended ? 2 : 1
                        )
                )
        )
    }

    private func benefitRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Text(icon)
                .font(.system(size: 18))
            Text(text)
                .font(.system(size: 16))
                .foregroundColor(.soyBrown)
            Spacer()
        }
    }
}
