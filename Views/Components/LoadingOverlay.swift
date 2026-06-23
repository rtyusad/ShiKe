import SwiftUI

/// 通用加载遮罩组件
struct LoadingOverlay: View {
    var message: String?

    var body: some View {
        ZStack {
            Color.black.opacity(0.15)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(.wokOrange)

                if let message = message {
                    Text(message)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
            }
            .padding(24)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}
