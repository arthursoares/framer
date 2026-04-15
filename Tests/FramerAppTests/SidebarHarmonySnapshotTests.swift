import XCTest
import AppKit
import CryptoKit
import SwiftUI
import FramerCore
@testable import Framer

@MainActor
final class SidebarHarmonySnapshotTests: XCTestCase {
    func test_styledToggleUsesToggleSemantics() {
        let bodyTypeName = String(reflecting: type(of: StyledToggle(isOn: .constant(true)).body))
        XCTAssertTrue(
            bodyTypeName.contains("Toggle"),
            "StyledToggle should be built from Toggle semantics. Body type: \(bodyTypeName)"
        )
    }

    func test_styledTogglePreservesHiddenTextLabelForAccessibility() {
        let bodyTypeName = String(reflecting: type(of: StyledToggle("Strip EXIF metadata", isOn: .constant(true)).body))
        XCTAssertTrue(
            bodyTypeName.contains("Text"),
            "StyledToggle should keep a hidden text label for accessibility. Body type: \(bodyTypeName)"
        )
    }

    func test_shellAndPolicyWiring() {
        let metrics = SidebarMetrics()

        XCTAssertEqual(metrics.minimumWidth, SidebarLayoutPolicy.default.minimumWidth)
        XCTAssertEqual(metrics.idealWidth, SidebarLayoutPolicy.default.idealWidth)
        XCTAssertEqual(metrics.maximumWidth, SidebarLayoutPolicy.default.maximumWidth)

        assertSnapshot(
            named: "sidebar-shell",
            of: SidebarShell {
                VStack(alignment: .leading, spacing: 16) {
                    SidebarSection("OUTPUT") {
                        SidebarControlRow("Format") {
                            FormatPicker(selection: .constant("png"))
                        }

                        SidebarControlRow("Strip EXIF metadata") {
                            EmptyView()
                        } trailingValue: {
                            StyledToggle(isOn: .constant(true))
                        }
                    }
                }
            } footer: {
                ExportBar()
                    .environment(makeExportState())
            },
            size: CGSize(width: 350, height: 320),
            expectedSHA256: "b20c44206984f99bf20b60e96161de8a98cfa4c71c19c1991cd9bbb5de616d2a"
        )
    }

    func test_layerRowStateVariants() {
        XCTAssertEqual(
            LayerPanelRowStateResolver.resolve(
                isExpanded: false,
                isHovering: false,
                isEnabled: true,
                isDragging: false,
                isDropTarget: false
            ),
            LayerPanelRowResolvedState(chassis: .default, availability: .default)
        )

        XCTAssertEqual(
            LayerPanelRowStateResolver.resolve(
                isExpanded: true,
                isHovering: false,
                isEnabled: true,
                isDragging: false,
                isDropTarget: false
            ),
            LayerPanelRowResolvedState(chassis: .expanded, availability: .default)
        )

        XCTAssertEqual(
            LayerPanelRowStateResolver.resolve(
                isExpanded: false,
                isHovering: false,
                isEnabled: false,
                isDragging: false,
                isDropTarget: false
            ),
            LayerPanelRowResolvedState(chassis: .default, availability: .disabled)
        )

        XCTAssertEqual(
            LayerPanelRowStateResolver.resolve(
                isExpanded: true,
                isHovering: true,
                isEnabled: true,
                isDragging: true,
                isDropTarget: true
            ),
            LayerPanelRowResolvedState(chassis: .dropTarget, availability: .default)
        )
    }

    func test_outputRows() {
        assertSnapshot(
            named: "output-rows-png",
            of: makeOutputRows(outputFormat: .png, stripMetadata: true),
            size: CGSize(width: 350, height: 200),
            expectedSHA256: "b850498e264cc7d19c75a119bbdffe1f358769fa6f41ef10f7577c54cd0f51f3"
        )

        assertSnapshot(
            named: "output-rows-jpeg",
            of: makeOutputRows(outputFormat: .jpeg(quality: 85), stripMetadata: false),
            size: CGSize(width: 350, height: 260),
            expectedSHA256: "7bbb9c9bf6f7915e38b8d58205c32a222c55729c5f350352ab0c0d90ced71436"
        )
    }

    func test_simpleEditorSurfaces() {
        assertSnapshot(
            named: "simple-canvas-editor",
            of: CanvasLayerControls(params: CanvasLayerParams()) { _ in },
            size: CGSize(width: 350, height: 420),
            expectedSHA256: "563371c5d78800b1c044688678ef7a10881a6fcdd21af8c76d8166d69eb439f8"
        )

        assertSnapshot(
            named: "simple-border-editor",
            of: BorderLayerControls(params: BorderLayerParams()) { _ in },
            size: CGSize(width: 350, height: 240),
            expectedSHA256: "0e0a0bc8667f07c296801a794b700e6f42f39b60826152f1566c69d00876c416"
        )
    }

    func test_denseEditorSurfaces() {
        assertSnapshot(
            named: "dense-caption-editor",
            of: CaptionLayerControls(params: CaptionLayerParams()) { _ in },
            size: CGSize(width: 350, height: 760),
            expectedSHA256: "28602a75b78845026b96eedd34079525320baba05146a91af6108f076425b883"
        )

        assertSnapshot(
            named: "dense-dither-editor",
            of: DitherLayerControls(params: DitherLayerParams()) { _ in },
            size: CGSize(width: 350, height: 900),
            expectedSHA256: "38b931598e5586f46521a5f25c5a688befab960d89b261a8693606a51e8b1375"
        )
    }

    func test_overlayEditorSurface() {
        assertSnapshot(
            named: "overlay-editor",
            of: OverlayLayerControls(params: OverlayLayerParams()) { _ in },
            size: CGSize(width: 350, height: 420),
            expectedSHA256: "2b3d8f00dced4d0e89bc2b583e3af5ec6c430ca058d5ef06e77811a4dc049c4e"
        )
    }

    func testPresetAndExportSurfaces() {
        assertSnapshot(
            named: "preset-grid-support-surfaces",
            of: PresetPreviewGrid()
                .environment(makePresetState()),
            size: CGSize(width: 350, height: 300),
            expectedSHA256: "7fa78863980d7d1884ff69a1c0f43c6815fe24e2d2e36dd20f521c7c41c2ded7"
        )

        assertSnapshot(
            named: "export-support-surfaces",
            of: VStack(alignment: .leading, spacing: 12) {
                ExportBar()
                ExportQueuePopover()
            }
            .environment(makeExportState())
            .background(Color.surface1),
            size: CGSize(width: 350, height: 320),
            expectedSHA256: "846a578704cc9e59d7b9bc1d72cc1ecb4fa151c429e345037a9fb426ee54307e"
        )
    }

    private func makeOutputRows(outputFormat: OutputFormat, stripMetadata: Bool) -> some View {
        SidebarSection("OUTPUT") {
            SidebarCompoundControlBlock {
                SidebarControlRow("Format") {
                    FormatPicker(selection: .constant(InspectorOutputControlState.formatSelection(for: outputFormat)))
                }
            } secondary: {
                if let jpegQuality = InspectorOutputControlState.jpegQuality(for: outputFormat) {
                    SidebarControlRow("Quality") {
                        StyledSlider(
                            value: .constant(jpegQuality),
                            range: 60...100,
                            step: 5,
                            suffix: "%"
                        )
                    }
                }
            }

            SidebarControlRow("Strip EXIF metadata") {
                EmptyView()
            } trailingValue: {
                StyledToggle(isOn: .constant(stripMetadata))
                    .padding(.trailing, 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.surface1)
    }

    private func makePresetState() -> AppState {
        let state = AppState()
        state.presets = [
            Preset(name: "Balanced", config: .default),
            Preset(name: "Vintage", config: .default),
        ]
        state.activePresetName = "Balanced"
        state.appliedPresetConfig = .default
        state.currentConfig = .default
        state.library = [PhotoItem(url: URL(fileURLWithPath: "/tmp/sample-balanced.jpg"))]
        state.selectedItems = [state.library[0].id]
        return state
    }

    private func makeExportState() -> AppState {
        let state = AppState()
        let photo1 = PhotoItem(url: URL(fileURLWithPath: "/tmp/export-a.jpg"))
        let photo2 = PhotoItem(url: URL(fileURLWithPath: "/tmp/export-b.jpg"))
        let outputDirectory = URL(fileURLWithPath: "/tmp")

        state.currentConfig = .default
        state.library = [photo1, photo2]
        state.selectedItems = [photo1.id]
        state.presets = [Preset(name: "Balanced", config: .default)]

        var running = ExportJob(items: [photo1, photo2], config: .default, outputDirectory: outputDirectory, label: "balanced")
        running.status = .running
        running.progress = 0.5
        running.completedCount = 1

        var done = ExportJob(items: [photo1], config: .default, outputDirectory: outputDirectory, label: "done")
        done.status = .done
        done.progress = 1
        done.completedCount = 1

        var failed = ExportJob(items: [photo2], config: .default, outputDirectory: outputDirectory, label: "failed")
        failed.status = .failed("1 of 1 failed")

        var cancelled = ExportJob(items: [photo1], config: .default, outputDirectory: outputDirectory, label: "cancelled")
        cancelled.status = .cancelled

        state.exportQueue = [running, done, failed, cancelled]
        return state
    }

    private func assertSnapshot<V: View>(
        named name: String,
        of view: V,
        size: CGSize,
        expectedSHA256: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let rootView = view
            .environment(\.colorScheme, .dark)
            .frame(width: size.width, height: size.height, alignment: .topLeading)

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.appearance = NSAppearance(named: .darkAqua)
        hostingView.frame = CGRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            XCTFail("Failed to create bitmap for snapshot \(name)", file: file, line: line)
            return
        }

        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            XCTFail("Failed to encode PNG for snapshot \(name)", file: file, line: line)
            return
        }

        let actualSHA256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(
            actualSHA256,
            expectedSHA256,
            "Snapshot \(name) changed. Actual SHA256: \(actualSHA256)",
            file: file,
            line: line
        )
    }
}
