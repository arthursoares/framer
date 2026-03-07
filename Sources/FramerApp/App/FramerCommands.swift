import SwiftUI

struct FramerCommands: Commands {
    let appState: AppState

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open Photos...") {
                NotificationCenter.default.post(name: .framerOpenPhotos, object: nil)
            }
            .keyboardShortcut("o", modifiers: .command)
        }

        CommandMenu("Export") {
            Button("Export Selected") {
                NotificationCenter.default.post(name: .framerExportSelected, object: nil)
            }
            .keyboardShortcut("e", modifiers: .command)

            Button("Export All") {
                NotificationCenter.default.post(name: .framerExportAll, object: nil)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
        }

        CommandGroup(after: .pasteboard) {
            Button("Select All") {
                NotificationCenter.default.post(name: .framerSelectAll, object: nil)
            }
            .keyboardShortcut("a", modifiers: .command)

            Button("Delete Selected") {
                NotificationCenter.default.post(name: .framerDeleteSelected, object: nil)
            }
            .keyboardShortcut(.delete, modifiers: [])
        }

    }
}

extension Notification.Name {
    static let framerOpenPhotos = Notification.Name("framer.openPhotos")
    static let framerExportSelected = Notification.Name("framer.exportSelected")
    static let framerExportAll = Notification.Name("framer.exportAll")
    static let framerSelectAll = Notification.Name("framer.selectAll")
    static let framerDeleteSelected = Notification.Name("framer.deleteSelected")
}
