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
            size: CGSize(width: 352, height: 320),
            expectedSHA256: "f8e60d36c6341b104069d6dc105b3f61d9069886edfb5c8717c1ef4a5aa113de"
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
            size: CGSize(width: 320, height: 200),
            expectedSHA256: "ed1934c3073e88d00d9c73eda8719bc1ed2fef3c833d6542665a861f009d5b88"
        )

        assertSnapshot(
            named: "output-rows-jpeg",
            of: makeOutputRows(outputFormat: .jpeg(quality: 85), stripMetadata: false),
            size: CGSize(width: 320, height: 260),
            expectedSHA256: "099830b4a04d89b8a31a48e4196ecd7e089009559ef4ea151cc27270ca26ea11"
        )
    }

    func test_simpleEditorSurfaces() {
        assertSnapshot(
            named: "simple-canvas-editor",
            of: CanvasLayerControls(params: CanvasLayerParams()) { _ in },
            size: CGSize(width: 320, height: 420),
            expectedSHA256: "5f9aa79f0665244659dc03a542b148ce452f5360c21250c580a804d9bb114f63"
        )

        assertSnapshot(
            named: "simple-border-editor",
            of: BorderLayerControls(params: BorderLayerParams()) { _ in },
            size: CGSize(width: 320, height: 240),
            expectedSHA256: "ab7f2988ec778a1ee5f9f79e98069ec5efffaa16bb29829d000e69771938db9d"
        )
    }

    func test_denseEditorSurfaces() {
        assertSnapshot(
            named: "dense-caption-editor",
            of: CaptionLayerControls(params: CaptionLayerParams()) { _ in },
            size: CGSize(width: 320, height: 760),
            expectedSHA256: "bdf65dd94a7954463e8099fc87ba16c337410e22c315dcaf037f80f3298aeafe"
        )

        assertSnapshot(
            named: "dense-dither-editor",
            of: DitherLayerControls(params: DitherLayerParams()) { _ in },
            size: CGSize(width: 320, height: 900),
            expectedSHA256: "bc8380c207a59d77d3c2ee05cf5034795c2d106bb1877ad087a213f6566c2292"
        )
    }

    func test_overlayEditorSurface() {
        assertSnapshot(
            named: "overlay-editor",
            of: OverlayLayerControls(params: OverlayLayerParams()) { _ in },
            size: CGSize(width: 320, height: 420),
            expectedSHA256: "484cbf91109c9f3510ce610ffc22fcf6dd48582fb5682706c82ad9918bcf891d"
        )
    }

    func testPresetAndExportSurfaces() {
        assertSnapshot(
            named: "preset-grid-support-surfaces",
            of: PresetPreviewGrid()
                .environment(makePresetState()),
            size: CGSize(width: 320, height: 300),
            expectedSHA256: "b77fe54e409d918ec86ef1be58d5ed3fa5b8989ec422183bdbbda3bd5445ad7d"
        )

        assertSnapshot(
            named: "export-support-surfaces",
            of: VStack(alignment: .leading, spacing: 12) {
                ExportBar()
                ExportQueuePopover()
            }
            .environment(makeExportState())
            .background(Color.surface1),
            size: CGSize(width: 320, height: 320),
            expectedSHA256: "9df57737cf5950568ba52fcaa189ce02763062082b88cc9fbea296d0e511f883"
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
