import SwiftUI
import FramerCore

struct LayerDetailView: View {
    @Binding var layer: CompositionLayer
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Layer header
                HStack(spacing: 12) {
                    Image(systemName: layer.iconName)
                        .font(.system(size: 18))
                        .foregroundStyle(Color.accent)
                        .frame(width: 36, height: 36)
                        .background(Color.surface3, in: RoundedRectangle(cornerRadius: CornerRadius.md))

                    Text(layer.label)
                        .font(AppFont.body(22, weight: .bold))
                        .foregroundStyle(Color.text0)
                }
                .padding(.horizontal, 16)

                // Controls placeholder — will be implemented per layer type
                VStack(spacing: 12) {
                    Text("Layer controls coming soon")
                        .font(AppFont.controlLabel)
                        .foregroundStyle(Color.text3)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                }
                .padding(.horizontal, 16)

                Spacer(minLength: 20)

                // Delete button
                Button(role: .destructive) {
                    onDelete()
                    dismiss()
                } label: {
                    Text("Delete Layer")
                        .font(AppFont.buttonText)
                        .foregroundStyle(Color.error)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.surface2, in: RoundedRectangle(cornerRadius: CornerRadius.lg))
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 16)
        }
        .background(Color.surface0)
        .navigationTitle(layer.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.surface1, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .foregroundStyle(Color.text1)
        .tint(Color.accent)
    }
}
