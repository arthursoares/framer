import Foundation

/// A user-named colour palette, reusable across the Dither layer and the
/// GPU-effect palette colour mode.
public struct UserPalette: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var colors: [CodableColor]

    public init(id: UUID = UUID(), name: String, colors: [CodableColor]) {
        self.id = id
        self.name = name
        self.colors = colors
    }
}

/// JSON-file persistence for user palettes. Single `palettes.json` next to
/// the preset store's directory (Application Support/Framer/) — palettes are
/// tiny, so one file read/written whole keeps this trivial.
public final class UserPaletteStore {
    private let fileURL: URL

    public convenience init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = appSupport.appendingPathComponent("Framer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.init(fileURL: dir.appendingPathComponent("palettes.json"))
    }

    /// Testable initializer with a custom file location.
    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func list() -> [UserPalette] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([UserPalette].self, from: data)) ?? []
    }

    /// Insert or update (by id). Names are not required to be unique —
    /// the id is the identity; duplicate names are the user's choice.
    public func save(_ palette: UserPalette) throws {
        var palettes = list()
        if let idx = palettes.firstIndex(where: { $0.id == palette.id }) {
            palettes[idx] = palette
        } else {
            palettes.append(palette)
        }
        try write(palettes)
    }

    public func delete(id: UUID) throws {
        var palettes = list()
        palettes.removeAll { $0.id == id }
        try write(palettes)
    }

    private func write(_ palettes: [UserPalette]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(palettes)
        try data.write(to: fileURL, options: .atomic)
    }
}
