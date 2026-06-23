import SwiftUI

/// 链接输入框组件（AC07: 来源标注设计配套）
struct URLInputField: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .foregroundColor(isFocused ? .wokOrange : .secondary)

                TextField("粘贴 B 站视频链接", text: $text)
                    .font(.system(size: 15))
                    .focused($isFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                isFocused ? Color.wokOrange : Color.gray.opacity(0.2),
                                lineWidth: isFocused ? 1.5 : 1
                            )
                    )
            )

            // 示例链接
            if text.isEmpty && !isFocused {
                Text("例：https://www.bilibili.com/video/BV1xx411c7mD")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary.opacity(0.6))
                    .padding(.leading, 4)
            }
        }
    }
}
