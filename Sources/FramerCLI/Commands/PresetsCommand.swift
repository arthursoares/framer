import ArgumentParser
import Foundation
import FramerCore

struct PresetsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "presets",
        abstract: "Manage presets",
        subcommands: [ListPresets.self]
    )

    struct ListPresets: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list")
        func run() throws {
            let store = PresetStore()
            let presets = try store.list()
            if presets.isEmpty {
                print("No presets saved.")
                return
            }
            for p in presets {
                print("  \(p.name) (\(p.id))")
            }
        }
    }
}
