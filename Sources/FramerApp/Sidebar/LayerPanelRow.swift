import SwiftUI
import FramerCore

struct LayerPanelRowResolvedState: Equatable, Sendable {
    let chassis: SidebarState
    let availability: SidebarState
}

enum LayerPanelRowStateResolver {
    static func resolve(
        isExpanded: Bool,
        isHovering: Bool,
        isEnabled: Bool,
        isDragging: Bool,
        isDropTarget: Bool
    ) -> LayerPanelRowResolvedState {
        let chassis: SidebarState

        if isDropTarget {
            chassis = .dropTarget
        } else if isDragging {
            chassis = .dragging
        } else if isExpanded {
            chassis = .expanded
        } else if isHovering {
            chassis = .hover
        } else {
            chassis = .default
        }

        return LayerPanelRowResolvedState(
            chassis: chassis,
            availability: isEnabled ? .default : .disabled
        )
    }
}

struct LayerPanelRow: View {
    @Binding var layer: CompositionLayer
    let isDragging: Bool
    let isDropTarget: Bool
    let onDelete: () -> Void
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?

    @State private var isHovering = false
    @State private var isExpanded = false
    @State private var isHoveringVisibilityToggle = false
    @State private var isHoveringDelete = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: LayerPanelRowLayout.headerSpacing) {
                Button(action: toggleExpanded) {
                    HStack(spacing: LayerPanelRowLayout.headerSpacing) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.text3)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .frame(width: LayerPanelRowLayout.disclosureSize, height: LayerPanelRowLayout.disclosureSize)

                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.text3)
                            .frame(width: LayerPanelRowLayout.handleWidth)
                            .opacity(0.6)

                        Image(systemName: layer.iconName)
                            .foregroundStyle(iconColor)
                            .frame(width: LayerPanelRowLayout.iconWidth)

                        Text(layer.label)
                            .font(AppFont.layerName)
                            .foregroundStyle(titleColor)

                        Spacer()

                        Text(layerSummary)
                            .font(AppFont.badgeSummary)
                            .foregroundStyle(summaryColor)
                            .padding(.horizontal, LayerPanelRowLayout.badgeHorizontalPadding)
                            .padding(.vertical, LayerPanelRowLayout.badgeVerticalPadding)
                            .background(Color.surface4, in: Capsule())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(layer.label)
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                .accessibilityHint("Expand or collapse layer controls")

                Button {
                    layer.isEnabled.toggle()
                } label: {
                    Image(systemName: layer.isEnabled ? "eye" : "eye.slash")
                        .font(.caption)
                        .foregroundStyle(visibilityIconColor)
                        .frame(width: LayerPanelRowLayout.visibilityWidth, height: LayerPanelRowLayout.visibilityHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { isHoveringVisibilityToggle = $0 }
                .accessibilityLabel(layer.isEnabled ? "Disable layer" : "Enable layer")

                Button {
                    onDelete()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(deleteIconColor)
                        .frame(width: LayerPanelRowLayout.deleteWidth, height: LayerPanelRowLayout.deleteHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { isHoveringDelete = $0 }
                .opacity(isHovering ? 1 : 0.4)
                .animation(LayerPanelRowLayout.hoverAnimation, value: isHovering)
                .accessibilityLabel("Delete layer")
            }
            .padding(.horizontal, LayerPanelRowLayout.headerHorizontalPadding)
            .padding(.vertical, LayerPanelRowLayout.headerVerticalPadding)
            .onHover { isHovering = $0 }

            if isExpanded {
                VStack(alignment: .leading, spacing: LayerPanelRowLayout.controlsSpacing) {
                    layerControls
                }
                .padding(.top, LayerPanelRowLayout.expandedTopPadding)
                .padding(.bottom, LayerPanelRowLayout.expandedBottomPadding)
                .padding(.leading, LayerPanelRowLayout.expandedLeadingPadding)
                .padding(.trailing, LayerPanelRowLayout.expandedTrailingPadding)
                .foregroundStyle(Color.text1)
                .tint(Color.accent)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(chassisStyle.backgroundColor)
        )
        .opacity(rowOpacity)
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .stroke(chassisStyle.borderColor, lineWidth: 1)
        )
        .contextMenu {
            if let onMoveUp {
                Button { onMoveUp() } label: {
                    Label("Move Up", systemImage: "chevron.up")
                }
            }

            if let onMoveDown {
                Button { onMoveDown() } label: {
                    Label("Move Down", systemImage: "chevron.down")
                }
            }

            Divider()

            Button {
                layer.isEnabled.toggle()
            } label: {
                Label(
                    layer.isEnabled ? "Disable Layer" : "Enable Layer",
                    systemImage: layer.isEnabled ? "eye.slash" : "eye"
                )
            }

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete Layer", systemImage: "trash")
            }
        }
    }

    private var resolvedState: LayerPanelRowResolvedState {
        LayerPanelRowStateResolver.resolve(
            isExpanded: isExpanded,
            isHovering: isHovering,
            isEnabled: layer.isEnabled,
            isDragging: isDragging,
            isDropTarget: isDropTarget
        )
    }

    private var chassisStyle: SidebarStateStyle {
        SidebarStateStyle.style(for: resolvedState.chassis)
    }

    private var availabilityStyle: SidebarStateStyle {
        SidebarStateStyle.style(for: resolvedState.availability)
    }

    private var rowOpacity: Double {
        resolvedState.chassis == .dragging ? chassisStyle.opacity : availabilityStyle.opacity
    }

    private var titleColor: Color {
        resolvedState.availability == .disabled ? availabilityStyle.foregroundColor : chassisStyle.foregroundColor
    }

    private var iconColor: Color {
        resolvedState.availability == .disabled ? availabilityStyle.foregroundColor : Color.text2
    }

    private var summaryColor: Color {
        resolvedState.availability == .disabled ? availabilityStyle.foregroundColor : Color.text2
    }

    private var visibilityIconColor: Color {
        if isHoveringVisibilityToggle {
            return Color.text1
        }

        return layer.isEnabled ? Color.text2 : Color.text3
    }

    private var deleteIconColor: Color {
        isHoveringDelete ? Color.error : Color.text3
    }

    private func toggleExpanded() {
        withAnimation(LayerPanelRowLayout.expandAnimation) {
            isExpanded.toggle()
        }
    }

    @ViewBuilder
    private var layerControls: some View {
        switch layer {
        case .border(let params):
            BorderLayerControls(params: params) { layer = .border($0) }
        case .padding(let params):
            PaddingLayerControls(params: params) { layer = .padding($0) }
        case .canvas(let params):
            CanvasLayerControls(params: params) { layer = .canvas($0) }
        case .resize(let params):
            ResizeLayerControls(params: params) { layer = .resize($0) }
        case .overlay(let params):
            OverlayLayerControls(params: params) { layer = .overlay($0) }
        case .orientation(let params):
            OrientationLayerControls(params: params) { layer = .orientation($0) }
        case .caption(let params):
            CaptionLayerControls(params: params) { layer = .caption($0) }
        case .dither(let params):
            DitherLayerControls(params: params) { layer = .dither($0) }
        case .aspectRatio(let params):
            AspectRatioLayerControls(params: params) { layer = .aspectRatio($0) }
        case .lut(let params):
            LUTLayerControls(params: params) { layer = .lut($0) }
        case .shader(let params):
            ShaderLayerControls(params: params) { layer = .shader($0) }
        case .gpuEffect(let params):
            GPUEffectLayerControls(params: params) { layer = .gpuEffect($0) }
        }
    }

    private var layerSummary: String {
        if !layer.isEnabled {
            return "Disabled"
        }

        switch layer {
        case .border(let params):
            switch params.thickness {
            case .pixels(let pixels):
                return "\(pixels)px"
            case .percent(let percent):
                return "\(Int(percent))%"
            }
        case .padding(let params):
            return "\(params.thickness)px"
        case .canvas(let params):
            return "\(params.width)x\(params.height)"
        case .resize(let params):
            return "max \(params.maxWidth)x\(params.maxHeight)"
        case .overlay(let params):
            if params.overlayName.isEmpty {
                return "None"
            }

            return "\(params.kind.label) \(Int(params.opacity))%"
        case .orientation(let params):
            return params.target.rawValue.capitalized
        case .caption(let params):
            switch params.mode {
            case .template:
                return "Template"
            case .custom:
                return "Custom"
            case .none:
                return "Off"
            }
        case .dither(let params):
            return params.algorithm.label
        case .aspectRatio(let params):
            return "\(params.ratioWidth):\(params.ratioHeight)"
        case .lut(let params):
            return params.lutName.isEmpty ? "None" : params.lutName
        case .shader(let params):
            return params.style.label
        case .gpuEffect(let params):
            return params.kind.label
        }
    }
}

private enum LayerPanelRowLayout {
    static let headerSpacing = Spacing.sm
    static let disclosureSize = Spacing.xl
    static let handleWidth = Spacing.xl + Spacing.xs
    static let iconWidth = Spacing.xl + Spacing.xs
    static let badgeHorizontalPadding = Spacing.sm
    static let badgeVerticalPadding = Spacing.xs / 2
    static let visibilityWidth = Spacing.xl + (Spacing.xs * 2)
    static let visibilityHeight = Spacing.xl + Spacing.xs
    static let deleteWidth = Spacing.xl + Spacing.xs
    static let deleteHeight = Spacing.xl + Spacing.xs
    static let headerHorizontalPadding = Spacing.xs * 2
    static let headerVerticalPadding = Spacing.xs * 2
    static let controlsSpacing = Spacing.md
    static let expandedTopPadding = Spacing.xs * 2
    static let expandedBottomPadding = Spacing.sm * 2
    static let expandedLeadingPadding = Spacing.xl + Spacing.xs
    static let expandedTrailingPadding = Spacing.xs
    static let hoverAnimation = Animation.easeInOut(duration: 0.15)
    static let expandAnimation = Animation.easeInOut(duration: 0.15)
}
