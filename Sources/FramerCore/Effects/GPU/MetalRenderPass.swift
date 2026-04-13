// MetalRenderPass.swift
// Thin command-buffer wrapper used by every Effects bucket renderer.
//
// Each bucket renderer prepares a pipeline + textures + a uniform byte buffer,
// then calls `MetalRenderPass.encode(...)` to schedule a fullscreen-triangle
// draw into a private output texture. The helper handles the boilerplate:
// pass descriptor, encoder lifecycle, sampler binding, command buffer commit,
// and synchronous wait. Returning the output texture (rather than a CGImage)
// lets callers either chain another pass or read it back via
// `MetalTextureSupport.makeCGImage`.

import Foundation
import Metal

public enum MetalRenderPass {

    /// Auxiliary textures bound to fragment texture indices `1..n`. Order
    /// matters — index `i` in the array binds to fragment texture slot `i + 1`.
    /// Used for atlas / LUT inputs (e.g. ASCII edges + fill atlases).
    public typealias AuxiliaryTexture = MTLTexture

    /// Encode and submit one fullscreen-triangle render pass.
    ///
    /// - Parameters:
    ///   - pipeline:       `MTLRenderPipelineState` from `MetalEffectLibrary.pipeline(for:)`.
    ///   - source:         Fragment texture slot 0 (typically the source image).
    ///   - auxTextures:    Optional extra fragment textures, slots 1+.
    ///   - sampler:        Sampler bound to fragment sampler slot 0.
    ///   - uniformBytes:   `Data` containing the packed uniform struct.
    ///                     Mirror MSL layout exactly.
    ///   - outputSize:     Pixel dimensions of the destination texture.
    ///   - library:        Metal library + queue (defaults to `.shared`).
    /// - Returns: Private-storage `MTLTexture` containing the rendered result.
    public static func encode(
        pipeline: MTLRenderPipelineState,
        source: MTLTexture,
        auxTextures: [AuxiliaryTexture] = [],
        sampler: MTLSamplerState,
        uniformBytes: Data,
        outputSize: (width: Int, height: Int),
        library: MetalEffectLibrary
    ) throws -> MTLTexture {
        let outputTexture = try MetalTextureSupport.makeRenderTarget(
            width: outputSize.width,
            height: outputSize.height,
            device: library.device
        )

        guard let commandBuffer = library.commandQueue.makeCommandBuffer() else {
            throw MetalEffectError.commandEncodingFailed
        }

        let passDescriptor = MTLRenderPassDescriptor()
        passDescriptor.colorAttachments[0].texture = outputTexture
        passDescriptor.colorAttachments[0].loadAction = .clear
        passDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        passDescriptor.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else {
            throw MetalEffectError.commandEncodingFailed
        }

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(source, index: 0)
        for (offset, tex) in auxTextures.enumerated() {
            encoder.setFragmentTexture(tex, index: offset + 1)
        }
        encoder.setFragmentSamplerState(sampler, index: 0)

        // Inline uniform upload: small payloads (≤ 4 KB) fit through
        // setFragmentBytes without allocating an MTLBuffer.
        uniformBytes.withUnsafeBytes { rawBuffer in
            if let baseAddress = rawBuffer.baseAddress, !rawBuffer.isEmpty {
                encoder.setFragmentBytes(baseAddress, length: rawBuffer.count, index: 0)
            }
        }

        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        // Surface driver-level GPU runtime errors (texture bind violation, OOM,
        // device removal, timeout) as MetalEffectError so gpuOrCPU() can fall
        // back to CPU. Without this, an .error status returns garbage pixels
        // silently and the caller treats the corrupt output as success.
        if commandBuffer.status != .completed {
            throw MetalEffectError.commandEncodingFailed
        }

        return outputTexture
    }
}
