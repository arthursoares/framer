import SwiftUI

struct FormatPicker: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 0) {
            pillButton("JPEG", tag: "jpeg")
            pillButton("PNG", tag: "png")
        }
        .background(Color.surface3, in: Capsule())
    }

    private func pillButton(_ label: String, tag: String) -> some View {
        Button {
            selection = tag
        } label: {
            Text(label)
                .font(AppFont.buttonText)
                .foregroundStyle(selection == tag ? Color.accent : Color.text2)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(selection == tag ? Color.accentSubtle : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
