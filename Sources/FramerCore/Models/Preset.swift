import Foundation

public struct Preset: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var config: ProcessingConfig
    public var thumbnailData: Data?

    public init(id: UUID = .init(), name: String, config: ProcessingConfig, thumbnailData: Data? = nil) {
        self.id = id
        self.name = name
        self.config = config
        self.thumbnailData = thumbnailData
    }
}
