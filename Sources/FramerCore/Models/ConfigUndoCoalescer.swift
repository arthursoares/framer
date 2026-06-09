import Foundation

/// Coalescing undo for `ProcessingConfig` edits.
///
/// Hook `onChange(of: appState.currentConfig)` at the platform root and feed
/// every mutation through `configChanged`. One undo entry is registered per
/// *editing burst* — a slider drag emits dozens of changes per second, but
/// ⌘Z should restore the value before the drag, not replay it tick by tick.
/// A burst ends after 300 ms without changes.
///
/// This replaces per-control `registerUndo` plumbing: with the single hook,
/// every control (sliders, pickers, color wells, layer add/move/delete,
/// preset application) is undoable through one mechanism.
@MainActor
public final class ConfigUndoCoalescer {
    private var burstActive = false
    private var burstTask: Task<Void, Never>?
    /// Set just before an undo/redo restore mutates the config so the
    /// resulting `onChange` notification isn't recorded as a fresh edit.
    private var expectedRestore: ProcessingConfig?

    public init() {}

    /// Feed every observed config change here.
    /// - Parameters:
    ///   - current: reads the live config (used at undo time to build redo).
    ///   - restore: writes the config back (the undo/redo action).
    public func configChanged(
        from old: ProcessingConfig,
        to new: ProcessingConfig,
        undoManager: UndoManager?,
        current: @escaping @MainActor () -> ProcessingConfig,
        restore: @escaping @MainActor (ProcessingConfig) -> Void
    ) {
        if let expected = expectedRestore, expected == new {
            expectedRestore = nil
            return
        }
        guard old != new, let undoManager else { return }

        if !burstActive {
            burstActive = true
            register(baseline: old, undoManager: undoManager, current: current, restore: restore)
        }
        burstTask?.cancel()
        burstTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.burstActive = false
        }
    }

    private func register(
        baseline: ProcessingConfig,
        undoManager: UndoManager,
        current: @escaping @MainActor () -> ProcessingConfig,
        restore: @escaping @MainActor (ProcessingConfig) -> Void
    ) {
        undoManager.registerUndo(withTarget: self) { [weak undoManager] coalescer in
            MainActor.assumeIsolated {
                // Registering while an undo executes lands the entry on the
                // redo stack — this is what makes redo work.
                if let undoManager {
                    coalescer.register(
                        baseline: current(),
                        undoManager: undoManager,
                        current: current,
                        restore: restore
                    )
                }
                coalescer.burstTask?.cancel()
                coalescer.burstActive = false
                coalescer.expectedRestore = baseline
                restore(baseline)
            }
        }
        undoManager.setActionName("Edit")
    }
}
