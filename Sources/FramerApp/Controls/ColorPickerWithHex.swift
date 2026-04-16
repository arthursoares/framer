import SwiftUI
import FramerCore

struct ColorPickerWithHex: View {
    let label: String
    @Binding var selection: Color
    var onHexCommit: ((CodableColor) -> Void)?
    @State private var hexText: String = ""
    @State private var suppressSync = false

    init(_ label: String, selection: Binding<Color>, onHexCommit: ((CodableColor) -> Void)? = nil) {
        self.label = label
        self._selection = selection
        self.onHexCommit = onHexCommit
    }

    var body: some View {
        HStack(spacing: 8) {
            ColorPicker(label, selection: $selection)
                .labelsHidden()
                .accessibilityLabel(Text(label))
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
                .accessibilityLabel(Text("\(label) hex value"))
        }
        .onAppear { syncHexFromColor() }
        .onChange(of: selection) { _, _ in
            if suppressSync {
                suppressSync = false
            } else {
                syncHexFromColor()
            }
        }
    }

    private func syncHexFromColor() {
        if let hex = selection.hexString {
            hexText = hex
        }
    }

    private func applyHex() {
        let cleaned = hexText.trimmingCharacters(in: .whitespaces)
        guard let codable = try? CodableColor(hex: cleaned) else { return }

        // Direct hex callback bypasses Color round-trip entirely
        if let onHexCommit {
            onHexCommit(codable)
            hexText = codable.hex
            return
        }

        // Update through the Color binding — suppress the sync so our hex isn't overwritten
        suppressSync = true
        let nsColor = NSColor(
            colorSpace: .sRGB,
            components: [CGFloat(codable.red), CGFloat(codable.green), CGFloat(codable.blue), 1.0],
            count: 4
        )
        selection = Color(nsColor: nsColor)
        hexText = codable.hex
    }
}
