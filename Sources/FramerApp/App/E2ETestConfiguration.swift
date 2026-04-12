import Foundation

struct AppE2ETestConfiguration {
    let fixturesDirectory: URL
    let exportDirectory: URL
    let presetName: String?

    static func load(from environment: [String: String] = ProcessInfo.processInfo.environment) -> AppE2ETestConfiguration? {
        guard environment["FRAMER_E2E_MODE"] == "1",
              let fixtures = environment["FRAMER_E2E_FIXTURE_DIR"],
              let export = environment["FRAMER_E2E_EXPORT_DIR"] else {
            return nil
        }

        return AppE2ETestConfiguration(
            fixturesDirectory: URL(fileURLWithPath: fixtures),
            exportDirectory: URL(fileURLWithPath: export),
            presetName: environment["FRAMER_E2E_PRESET_NAME"]
        )
    }
}
