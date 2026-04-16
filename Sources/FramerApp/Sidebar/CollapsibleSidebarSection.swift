import SwiftUI

/// A `SidebarSection` variant whose body can be toggled between an expanded
/// state (full `content`) and a collapsed state (optional `collapsedContent`
/// shown under the header; typically a compact summary, or nothing).
///
/// The header row becomes a `Button` that flips the bound `isExpanded`
/// state with a short easing animation. A chevron on the right rotates
/// 90° to reflect the current state, matching the visual language of
/// `LayerPanelRow`'s disclosure control.
struct CollapsibleSidebarSection<Content: View, CollapsedContent: View>: View {
    @Environment(\.sidebarMetrics) private var envMetrics
    private let overrideMetrics: SidebarMetrics?
    private let title: LocalizedStringKey
    @Binding private var isExpanded: Bool
    private let content: Content
    private let collapsedContent: CollapsedContent

    init(
        _ title: LocalizedStringKey,
        isExpanded: Binding<Bool>,
        metrics: SidebarMetrics? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder collapsedContent: () -> CollapsedContent
    ) {
        self.title = title
        self._isExpanded = isExpanded
        self.overrideMetrics = metrics
        self.content = content()
        self.collapsedContent = collapsedContent()
    }

    private var metrics: SidebarMetrics { overrideMetrics ?? envMetrics }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.expandedBodyInset) {
            Button {
                // State toggle is intentionally bare — the `.animation(_:value:)`
                // modifier below drives the transition. `withAnimation` inside
                // the button action conflicts with SwiftUI's preferred
                // transaction propagation.
                isExpanded.toggle()
            } label: {
                HStack(spacing: metrics.expandedBodyInset) {
                    Text(title)
                        .font(AppFont.sectionHeader)
                        .tracking(1.5)
                        .foregroundStyle(Color.text3)

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.text3)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(Text(isExpanded ? "Expanded" : "Collapsed"))
            .accessibilityHint(Text("Toggle section"))

            // The conditional content block is wrapped in a VStack that's
            // clipped to its own bounds so the `.move(edge: .top)` transition
            // slides UP into its own space instead of briefly peeking above
            // the header row.
            VStack(alignment: .leading, spacing: 0) {
                if isExpanded {
                    content
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    collapsedContent
                        .transition(.opacity)
                }
            }
            .clipped()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.18), value: isExpanded)
    }
}

/// Convenience overload: collapsed state renders nothing beneath the header.
extension CollapsibleSidebarSection where CollapsedContent == EmptyView {
    init(
        _ title: LocalizedStringKey,
        isExpanded: Binding<Bool>,
        metrics: SidebarMetrics? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(title, isExpanded: isExpanded, metrics: metrics, content: content) {
            EmptyView()
        }
    }
}
