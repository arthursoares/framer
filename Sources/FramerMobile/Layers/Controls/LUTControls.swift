import SwiftUI
import FramerCore

// MARK: - LUT Controls

struct LUTControls: View {
    var params: LUTLayerParams
    var onChange: (LUTLayerParams) -> Void

    @State private var availableLUTs: [LUTInfo] = []
    @State private var showingPicker = false
    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(spacing: 8) {
            MobileBlendModeControls(
                blendMode: Binding(
                    get: { params.blendMode },
                    set: { var p = params; p.blendMode = $0; onChange(p) }
                ),
                opacity: Binding(
                    get: { params.opacity },
                    set: { var p = params; p.opacity = $0; onChange(p) }
                )
            )
            if availableLUTs.isEmpty {
                emptyState
            } else {
                ControlRow(label: "LUT") {
                    Picker("", selection: Binding(
                        get: { params.lutFileName },
                        set: { newValue in
                            var p = params
                            p.lutFileName = newValue
                            if let lut = availableLUTs.first(where: { $0.id == newValue }) {
                                p.lutName = lut.displayName
                            }
                            onChange(p)
                        }
                    )) {
                        Text("None").tag("")
                        ForEach(availableLUTs, id: \.id) { lut in
                            Text(lut.displayName).tag(lut.id)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            ControlRow(label: "Intensity") {
                HStack {
                    Slider(value: Binding(
                        get: { params.intensity },
                        set: { var p = params; p.intensity = $0; onChange(p) }
                    ), in: 0...1)
                    Text("\(Int(params.intensity * 100))%")
                        .font(AppFont.mono(12))
                        .frame(width: 50, alignment: .trailing)
                }
            }

            Button {
                showingPicker = true
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.down")
                    Text("Import LUT")
                }
                .font(AppFont.controlLabel)
                .foregroundStyle(Color.accent)
            }
            .sheet(isPresented: $showingPicker) {
                DocumentPickerView { url in
                    importLUT(from: url)
                }
            }
        }
        .onAppear {
            loadLUTs()
        }
        .alert("Import Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 32))
                .foregroundStyle(Color.text3)
            Text("No LUTs available")
                .font(AppFont.controlLabel)
                .foregroundStyle(Color.text3)
            Text("Import .cube files to get started")
                .font(.caption)
                .foregroundStyle(Color.text3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private func loadLUTs() {
        availableLUTs = LUTProvider.availableLUTs()
    }

    private func importLUT(from url: URL) {
        do {
            let info = try LUTProvider.importLUT(from: url)
            LUTProvider.invalidateCache()
            loadLUTs()
            var p = params
            p.lutName = info.displayName
            p.lutFileName = info.id
            onChange(p)
        } catch {
            errorMessage = "Failed to import LUT: \(error.localizedDescription)"
            showingError = true
        }
    }
}

// MARK: - Document Picker

private struct DocumentPickerView: UIViewControllerRepresentable {
    var onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data])
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    fileprivate func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    fileprivate final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var onPick: (URL) -> Void

        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            onPick(url)
        }
    }
}

