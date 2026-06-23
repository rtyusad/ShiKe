import SwiftUI

/// 食谱库空态视图
struct EmptyLibraryView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "book.pages")
                .font(.system(size: 64))
                .foregroundColor(.wokOrange.opacity(0.4))

            VStack(spacing: 8) {
                Text("还没有食谱")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.soyBrown)

                Text("点击下方「添加」按钮\n将 B 站美食视频转化为步骤卡片吧")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color.ricePaper)
    }
}
