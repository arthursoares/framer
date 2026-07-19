// EffectSeed.swift
// Shared seed derivation for seeded effects (RoughBorder, FilmGrain).

import Foundation

enum EffectSeed {
    /// FNV-1a over the identity string's UTF-8 bytes. Swift's `hashValue` is
    /// randomized per process — a seed derived from it would change on every
    /// launch, breaking preview/export agreement and re-run reproducibility.
    static func stableHash(_ identity: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in identity.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }

    /// Vary-per-image: fold a stable hash of the source filename into the
    /// seed so each image in a batch gets its own variation while the same
    /// image always reproduces the same result.
    static func effective(_ seed: Int, varyPerImage: Bool, identity: String?) -> Int {
        guard varyPerImage, let identity else { return seed }
        return seed &+ Int(truncatingIfNeeded: stableHash(identity))
    }

    /// Fold the integer seed into the float domain the shader noise hash
    /// reads. Modulo keeps precision: beyond ~2^24 a Float can no longer
    /// resolve adjacent seeds.
    static func uniformValue(_ seed: Int) -> Float {
        Float(((seed % 100_000) + 100_000) % 100_000)
    }
}
