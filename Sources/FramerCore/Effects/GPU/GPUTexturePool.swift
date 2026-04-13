import Foundation
import Metal

public actor GPUTexturePool {
    private var textures: [String: MTLTexture] = [:]

    public init() {}

    public func texture(for key: String) -> MTLTexture? {
        textures[key]
    }

    public func store(_ texture: MTLTexture, for key: String) {
        textures[key] = texture
    }

    public func removeAll() {
        textures.removeAll(keepingCapacity: true)
    }
}
