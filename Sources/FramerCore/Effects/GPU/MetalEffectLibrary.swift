// MetalEffectLibrary.swift
// Loads the FramerCore Metal library and caches render-pipeline + sampler state.
//
// The library is built by SPM at compile time: every .metal file under
// Sources/FramerCore/Effects/Metal/ is compiled into `default.metallib` placed
// inside `Bundle.module`. At first access we load it once via
// `device.makeDefaultLibrary(bundle:)`, then look up fragment functions by
// name (`textCellFragment`, `printSamplingFragment`, ...). The shared
// `fullscreenVertex` entry point is paired with whichever fragment is
// requested.
//
// Pipeline objects are expensive to build (they invoke the shader compiler) but
// cheap to bind, so we cache them keyed by fragment-function name.
//
// The two exposed sampler states match the patterns the .metal files expect:
//   - nearestClamp: pixel-perfect atlas reads (LUTs, glyph atlases)
//   - linearClamp:  smooth source-image sampling (down/upscale within shader)
//
// All accesses are protected by a single NSLock — these caches are read once
// per render call so contention is negligible.

import Foundation
import Metal

public enum MetalEffectError: Error {
    case metalUnavailable
    case libraryUnavailable(String)
    case functionMissing(String)
    case pipelineCreationFailed(String, underlying: Error?)
    case samplerCreationFailed
    case textureCreationFailed
    case textureLoadFailed(String)
    case readbackFailed
    case commandEncodingFailed
}

public final class MetalEffectLibrary: @unchecked Sendable {

    public static let shared = MetalEffectLibrary()

    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue

    private let library: MTLLibrary
    private let lock = NSLock()

    private var pipelineCache: [String: MTLRenderPipelineState] = [:]
    private var nearestClampSampler: MTLSamplerState?
    private var linearClampSampler: MTLSamplerState?

    /// Default vertex function name shared by all effect fragments.
    public static let defaultVertexFunctionName = "fullscreenVertex"

    private init?() {
        guard let dev = MTLCreateSystemDefaultDevice() else { return nil }
        guard let queue = dev.makeCommandQueue() else { return nil }

        // SPM + .metal compilation diverges across build contexts:
        //
        //   - Under Xcode (Framer.app build): SwiftPM's `.process(...)` rule
        //     for .metal files DOES invoke the Metal compiler toolchain via
        //     Xcode's build system, producing a `default.metallib` inside
        //     Bundle.module. The raw .metal source files are NOT copied.
        //
        //   - Under `swift build` / `swift test` / FramerCLI (no Xcode
        //     toolchain driver): SwiftPM 5.10 treats the .metal files as
        //     opaque resources and just copies them verbatim. No metallib
        //     gets generated.
        //
        // So we try the precompiled library first; if it's missing, fall
        // back to reading the .metal text resources and compiling at runtime.
        let bundle = Bundle.module

        if let lib = try? dev.makeDefaultLibrary(bundle: bundle) {
            self.device = dev
            self.commandQueue = queue
            self.library = lib
            return
        }

        guard
            let headerURL = bundle.url(forResource: "ShaderCommon", withExtension: "h"),
            let headerSource = try? String(contentsOf: headerURL, encoding: .utf8)
        else {
            print("MetalEffectLibrary: no default.metallib and no source fallback available in Bundle.module")
            return nil
        }

        let metalURLs = (bundle.urls(forResourcesWithExtension: "metal", subdirectory: nil) ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !metalURLs.isEmpty else {
            print("MetalEffectLibrary: ShaderCommon.h found but no .metal text resources in Bundle.module")
            return nil
        }

        var combined = headerSource + "\n"
        for url in metalURLs {
            guard let source = try? String(contentsOf: url, encoding: .utf8) else { continue }
            // Strip `#include "ShaderCommon.h"` lines — header is inlined above.
            let stripped = source
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix(#"#include "ShaderCommon.h""#) }
                .joined(separator: "\n")
            combined += "\n// === \(url.lastPathComponent) ===\n" + stripped + "\n"
        }

        let lib: MTLLibrary
        do {
            lib = try dev.makeLibrary(source: combined, options: nil)
        } catch {
            // Shader compile error — likely a syntax issue in one of the
            // .metal files. Surfaced here so it shows in CLI/test logs.
            print("MetalEffectLibrary: makeLibrary failed: \(error)")
            return nil
        }

        self.device = dev
        self.commandQueue = queue
        self.library = lib
    }

    // MARK: - Pipeline

    /// Fetch (or build and cache) a render pipeline keyed by fragment-function name.
    /// The vertex stage is always `fullscreenVertex`; the colour attachment is
    /// `.rgba8Unorm` so the output matches the CGImage readback path.
    public func pipeline(for fragmentFunctionName: String) throws -> MTLRenderPipelineState {
        lock.lock()
        defer { lock.unlock() }

        if let cached = pipelineCache[fragmentFunctionName] {
            return cached
        }

        guard let vertex = library.makeFunction(name: Self.defaultVertexFunctionName) else {
            throw MetalEffectError.functionMissing(Self.defaultVertexFunctionName)
        }
        guard let fragment = library.makeFunction(name: fragmentFunctionName) else {
            throw MetalEffectError.functionMissing(fragmentFunctionName)
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .rgba8Unorm

        let pipeline: MTLRenderPipelineState
        do {
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            throw MetalEffectError.pipelineCreationFailed(fragmentFunctionName, underlying: error)
        }

        pipelineCache[fragmentFunctionName] = pipeline
        return pipeline
    }

    // MARK: - Samplers

    /// Pixel-perfect nearest-neighbour sampler with edge clamping. Use for atlas
    /// reads where `texture.read()` is preferable but a sampler is required.
    public func nearestClamp() throws -> MTLSamplerState {
        lock.lock()
        defer { lock.unlock() }
        if let cached = nearestClampSampler { return cached }

        let desc = MTLSamplerDescriptor()
        desc.minFilter = .nearest
        desc.magFilter = .nearest
        desc.mipFilter = .nearest
        desc.sAddressMode = .clampToEdge
        desc.tAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: desc) else {
            throw MetalEffectError.samplerCreationFailed
        }
        nearestClampSampler = sampler
        return sampler
    }

    /// Smooth bilinear sampler with edge clamping. Use for arbitrary source
    /// sampling inside fragment shaders.
    public func linearClamp() throws -> MTLSamplerState {
        lock.lock()
        defer { lock.unlock() }
        if let cached = linearClampSampler { return cached }

        let desc = MTLSamplerDescriptor()
        desc.minFilter = .linear
        desc.magFilter = .linear
        desc.mipFilter = .nearest
        desc.sAddressMode = .clampToEdge
        desc.tAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: desc) else {
            throw MetalEffectError.samplerCreationFailed
        }
        linearClampSampler = sampler
        return sampler
    }
}
