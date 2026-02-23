import ArgumentParser
import AppKit

struct FontsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fonts",
        abstract: "List available system fonts"
    )

    @Flag(help: "Show all fonts, not just monospaced") var all = false

    func run() {
        let fonts = NSFontManager.shared.availableFontFamilies
        let filtered = all ? fonts : fonts.filter { isMonospaced($0) }
        filtered.sorted().forEach { print($0) }
    }

    private func isMonospaced(_ family: String) -> Bool {
        guard let font = NSFont(name: family, size: 12) else { return false }
        let traits = NSFontManager.shared.traits(of: font)
        return traits.contains(.fixedPitchFontMask)
    }
}
