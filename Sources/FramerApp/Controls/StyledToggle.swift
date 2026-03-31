import SwiftUI

struct StyledToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Capsule()
                .fill(isOn ? Color.accentDim : Color.surface4)
                .frame(width: 32, height: 18)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(isOn ? Color.text0 : Color.text2)
                        .frame(width: 12, height: 12)
                        .padding(3)
                }
        }
        .buttonStyle(.plain)
    }
}
