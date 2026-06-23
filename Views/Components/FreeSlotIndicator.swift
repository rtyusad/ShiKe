import SwiftUI

/// 免费额度指示器
/// 显示已用/总免费槽位 + 进度条
struct FreeSlotIndicator: View {
    let used: Int
    let total: Int

    var remaining: Int { total - used }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: remaining > 0 ? "tray" : "tray.full")
                .font(.caption)
                .foregroundColor(remaining > 0 ? .scallionGreen : .red)

            Text("免费额度: \(used)/\(total)")
                .font(.system(size: 13))
                .foregroundColor(.secondary)

            ProgressView(value: Double(used), total: Double(total))
                .tint(remaining > 0 ? .scallionGreen : .red)

            if remaining == 0 {
                Text("已满")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.red)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
