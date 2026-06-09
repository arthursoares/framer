import SwiftUI
import FramerCore
#if os(macOS)
import AppKit
#endif

struct ContentView: View {
    @Environment(AppState.self) var appState
    @Environment(\.undoManager) private var undoManager
    @State private var showOriginal = false
    @State private var undoCoalescer = ConfigUndoCoalescer()

    var body: some View {
        VStack(spacing: 0) {
            // Top menu bar — spans full width
            TopMenuBar(showOriginal: $showOriginal)

            // Main content
            mainSplitView
        }
        .frame(minWidth: 900, minHeight: 650)
        // Single undo hook for every config edit (sliders, pickers, layer
        // add/move/delete, preset application) — see ConfigUndoCoalescer.
        .onChange(of: appState.currentConfig) { old, new in
            undoCoalescer.configChanged(
                from: old,
                to: new,
                undoManager: undoManager,
                current: { appState.currentConfig },
                restore: { appState.currentConfig = $0 }
            )
        }
    }

    @ViewBuilder
    private var mainSplitView: some View {
        #if os(macOS)
        InspectorSplitView(showOriginal: $showOriginal)
        #else
        HStack(spacing: 0) {
            CanvasView(showOriginal: $showOriginal)
            InspectorView()
        }
        #endif
    }
}

#if os(macOS)
private struct InspectorSplitView: NSViewRepresentable {
    @Environment(AppState.self) private var appState
    @Binding var showOriginal: Bool

    @MainActor
    final class Coordinator: NSObject, NSSplitViewDelegate {
        let canvasController = NSHostingController(rootView: AnyView(EmptyView()))
        let inspectorController = NSHostingController(rootView: AnyView(EmptyView()))
        var widthPolicy: SidebarLayoutPolicy = .default
        var hasAppliedInitialSidebarWidth = false

        func splitView(_ splitView: NSSplitView, constrainSplitPosition proposedPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            let proposedSidebarWidth = splitView.bounds.width - proposedPosition - splitView.dividerThickness
            return widthPolicy.dividerPosition(
                forTotalWidth: splitView.bounds.width,
                dividerThickness: splitView.dividerThickness,
                proposedSidebarWidth: proposedSidebarWidth
            )
        }

        func applyInitialSidebarWidthIfNeeded(to splitView: NSSplitView) {
            guard !hasAppliedInitialSidebarWidth, splitView.arrangedSubviews.count == 2, splitView.bounds.width > 0 else {
                return
            }

            let desiredPosition = widthPolicy.dividerPosition(
                forTotalWidth: splitView.bounds.width,
                dividerThickness: splitView.dividerThickness,
                proposedSidebarWidth: widthPolicy.idealWidth
            )
            splitView.setPosition(desiredPosition, ofDividerAt: 0)
            hasAppliedInitialSidebarWidth = true
        }

        func enforceSidebarWidthBoundsIfNeeded(to splitView: NSSplitView) {
            guard hasAppliedInitialSidebarWidth, splitView.arrangedSubviews.count == 2, splitView.bounds.width > 0 else {
                return
            }

            let currentSidebarWidth = splitView.arrangedSubviews[1].frame.width
            guard let adjustedPosition = widthPolicy.adjustedDividerPosition(
                forTotalWidth: splitView.bounds.width,
                dividerThickness: splitView.dividerThickness,
                currentSidebarWidth: currentSidebarWidth
            ) else {
                return
            }

            splitView.setPosition(adjustedPosition, ofDividerAt: 0)
        }

        func synchronizeSidebarWidthIfNeeded(to splitView: NSSplitView) {
            applyInitialSidebarWidthIfNeeded(to: splitView)
            enforceSidebarWidthBoundsIfNeeded(to: splitView)
        }
    }

    @MainActor
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSSplitView {
        let splitView = SidebarAwareSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = context.coordinator
        splitView.onLayout = { [weak coordinator = context.coordinator] splitView in
            DispatchQueue.main.async {
                coordinator?.synchronizeSidebarWidthIfNeeded(to: splitView)
            }
        }

        let canvasController = context.coordinator.canvasController
        let inspectorController = context.coordinator.inspectorController
        context.coordinator.widthPolicy = .default

        canvasController.rootView = AnyView(CanvasView(showOriginal: $showOriginal).environment(appState))
        inspectorController.rootView = AnyView(InspectorView().environment(appState))

        canvasController.view.translatesAutoresizingMaskIntoConstraints = true
        inspectorController.view.translatesAutoresizingMaskIntoConstraints = true
        canvasController.view.autoresizingMask = [.width, .height]
        inspectorController.view.autoresizingMask = [.width, .height]

        splitView.addArrangedSubview(canvasController.view)
        splitView.addArrangedSubview(inspectorController.view)
        inspectorController.view.setFrameSize(NSSize(width: context.coordinator.widthPolicy.idealWidth, height: 0))

        splitView.setHoldingPriority(.defaultLow, forSubviewAt: 0)
        splitView.setHoldingPriority(.defaultHigh, forSubviewAt: 1)

        return splitView
    }

    func updateNSView(_ splitView: NSSplitView, context: Context) {
        let canvasController = context.coordinator.canvasController
        let inspectorController = context.coordinator.inspectorController

        canvasController.rootView = AnyView(CanvasView(showOriginal: $showOriginal).environment(appState))
        inspectorController.rootView = AnyView(InspectorView().environment(appState))

        context.coordinator.widthPolicy = .default
        context.coordinator.synchronizeSidebarWidthIfNeeded(to: splitView)
    }
}

private final class SidebarAwareSplitView: NSSplitView {
    var onLayout: ((NSSplitView) -> Void)?

    override func layout() {
        super.layout()
        onLayout?(self)
    }
}
#endif

// MARK: - Top Menu Bar

struct TopMenuBar: View {
    @Environment(AppState.self) var appState
    @Binding var showOriginal: Bool

    var body: some View {
        HStack {
            if appState.selectedPhoto != nil {
                BeforeAfterToggle(showOriginal: $showOriginal)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background {
            Color.surface1
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.borderDefault).frame(height: 1)
                }
        }
    }
}
