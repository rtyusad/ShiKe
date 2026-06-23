import SwiftUI

/// 步骤进度条 — ●●○○○ 风格
struct StepProgressBar: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(index < current ? Color.wokOrange : Color.gray.opacity(0.2))
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, 8)
    }
}
