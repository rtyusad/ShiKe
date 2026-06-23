import SwiftUI

/// 来源标注组件（AC07: 不可删除）
/// 每条食谱顶部永久显示 UP 主 + B 站原链接
struct SourceAttribution: View {
    let author: String
    let url: String
    let bvNumber: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "play.rectangle")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text("UP主: @\(author)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.soyBrown)

                Text(url)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.7))
                    .lineLimit(1)
            }

            Spacer()

            // 外链按钮
            Button {
                if let linkURL = URL(string: url) {
                    UIApplication.shared.open(linkURL)
                }
            } label: {
                Image(systemName: "arrow.up.forward")
                    .font(.caption)
                    .foregroundColor(.wokOrange)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.creamBackground)
    }
}

extension Color {
    static let creamBackground = Color(red: 0.98, green: 0.96, blue: 0.92)
}
