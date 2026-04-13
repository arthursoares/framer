// MetalUniformEncoding.swift
// Helper for packing uniform structs into a Data buffer that matches MSL's
// expected struct stride, not just the content size.
//
// Metal's debug validation checks the passed buffer length against the MSL
// struct's ALIGNMENT-ROUNDED stride (so a 152-byte struct with a float4 member
// has alignment 16 and therefore stride 160). Swift's `withUnsafeBytes(of:)`
// returns `MemoryLayout<T>.size` bytes (content only), which drops any trailing
// alignment padding. That mismatches MSL's stride and trips:
//
//   Fragment Function(x): argument uniforms[0] from Buffer(0) with offset(0)
//   and length(152) has space for 152 bytes, but argument has a length(160).
//
// Use `uniformBytes(_:)` instead of `withUnsafeBytes(of:) { Data($0) }` so the
// resulting Data is exactly stride bytes, padded with zeros for the trailing
// alignment slack. The MSL shader never reads those trailing bytes; Metal just
// needs them to exist.

import Foundation

/// Copy `value` into a `Data` of size `MemoryLayout<T>.stride`. The trailing
/// padding bytes (stride - size) are zero-initialised and never read by the
/// shader — Metal only checks the buffer length is >= stride.
public func uniformBytes<T>(_ value: T) -> Data {
    let stride = MemoryLayout<T>.stride
    var data = Data(count: stride)
    data.withUnsafeMutableBytes { dst in
        withUnsafeBytes(of: value) { src in
            _ = src.copyBytes(to: dst)
        }
    }
    return data
}
