import SwiftUI

/// 单帧缩略图组件
struct FrameThumbnail: View {
    let image: UIImage
    let timestamp: Int
    let isSelected: Bool
    let isMarked: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 45)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                // 标记对勾
                if isMarked {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.scallionGreen)
                        .background(Circle().fill(Color.white).frame(width: 14, height: 14))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(2)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        isSelected ? Color.wokOrange : (isMarked ? Color.scallionGreen : Color.clear),
                        lineWidth: isSelected ? 2 : (isMarked ? 1.5 : 0)
                    )
            )

            // 时间戳
            Text(formatTimestamp(timestamp))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(isSelected ? .wokOrange : .secondary)
        }
        .frame(width: 64)
    }

    private func formatTimestamp(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }
}
