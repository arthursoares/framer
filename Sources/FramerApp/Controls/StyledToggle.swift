import SwiftUI

struct StyledToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn)
            .labelsHidden()
            .toggleStyle(StyledToggleControlStyle())
            .accessibilityValue(isOn ? "On" : "Off")
    }
}

private struct StyledToggleControlStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            Capsule()
                .fill(configuration.isOn ? Color.accentDim : Color.surface4)
                .frame(width: 32, height: 18)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(configuration.isOn ? Color.text0 : Color.text2)
                        .frame(width: 12, height: 12)
                        .padding(3)
                }
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
    }
}
