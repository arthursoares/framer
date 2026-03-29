import SwiftUI
import FramerCore

struct ColorPickerWithHex: View {
    let label: String
    @Binding var selection: Color
    @State private var hexText: String = ""

    init(_ label: String, selection: Binding<Color>) {
        self.label = label
        self._selection = selection
    }

    var body: some View {
        HStack(spacing: 8) {
            ColorPicker(label, selection: $selection)
            TextField("#HEX", text: $hexText)
                .textFieldStyle(.plain)
                .font(AppFont.hexValue)
                .foregroundStyle(Color.text1)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .frame(width: 80)
                .background(Color.surface3, in: RoundedRectangle(cornerRadius: CornerRadius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.sm)
                        .stroke(Color.borderDefault, lineWidth: 1)
                )
                .onSubmit { applyHex() }
        }
        .onAppear { syncHexFromColor() }
        .onChange(of: selection) { _, _ in syncHexFromColor() }
    }

    private func syncHexFromColor() {
        if let hex = selection.hexString {
            hexText = hex
        }
    }

    private func applyHex() {
        let cleaned = hexText.trimmingCharacters(in: .whitespaces)
        guard let codable = try? CodableColor(hex: cleaned) else { return }
        if let nsColor = NSColor(cgColor: codable.cgColor) {
            selection = Color(nsColor: nsColor)
        }
    }
}
