import SwiftUI

struct PreferencesView: View {
    @AppStorage("defaultOutputFormat") private var defaultFormat = "jpeg"
    @AppStorage("defaultJPEGQuality") private var defaultQuality = 95
    @AppStorage("openFinderAfterExport") private var openFinder = true

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            outputTab
                .tabItem {
                    Label("Output", systemImage: "photo")
                }
        }
        .frame(width: 420, height: 240)
    }

    private var generalTab: some View {
        Form {
            Toggle("Open Finder after export", isOn: $openFinder)

            LabeledContent("Presets folder") {
                HStack {
                    Text(presetsPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Reveal") {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: presetsPath)
                    }
                    .controlSize(.small)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var outputTab: some View {
        Form {
            Picker("Default format", selection: $defaultFormat) {
                Text("JPEG").tag("jpeg")
                Text("PNG").tag("png")
            }

            if defaultFormat == "jpeg" {
                LabeledContent("Default quality") {
                    HStack {
                        Slider(
                            value: Binding(
                                get: { Double(defaultQuality) },
                                set: { defaultQuality = Int($0) }
                            ),
                            in: 60...100,
                            step: 5
                        )
                        Text("\(defaultQuality)%")
                            .monospacedDigit()
                            .frame(width: 40)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var presetsPath: String {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        return appSupport.appendingPathComponent("Framer/presets").path
    }
}
