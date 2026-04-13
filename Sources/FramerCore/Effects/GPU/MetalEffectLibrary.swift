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

        // SPM places the compiled metallib inside Bundle.module for the package
        // resource bundle. We try the bundle library first, then fall back to
        // the device default (for hosts that link the shaders into the binary).
        let lib: MTLLibrary
        if let bundleLib = try? dev.makeDefaultLibrary(bundle: .module) {
            lib = bundleLib
        } else if let systemLib = dev.makeDefaultLibrary() {
            lib = systemLib
        } else {
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
