// Sources/FramerCore/Processing/LUTMetalRenderer.swift
import Foundation
import Metal
import CoreGraphics

// MARK: - LUTMetalRenderer

public enum LUTMetalRenderer {
    #if canImport(Metal)
    private static let initLock = NSLock()
    private static var context: MetalContext?

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct LUTParams {
        int lutSize;
        float intensity;
        float3 domainMin;
        float3 scale;
    };

    kernel void applyLUT(
        texture2d<uint, access::read> inputTex [[texture(0)]],
        texture2d<uint, access::write> outputTex [[texture(1)]],
        texture3d<float, access::read> lutTex [[texture(2)]],
        constant LUTParams& params [[buffer(0)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= inputTex.get_width() || gid.y >= inputTex.get_height()) return;

        uint4 inputPixel = inputTex.read(gid);
        float4 color = float4(inputPixel) / 255.0;
        float maxIndex = float(params.lutSize - 1);

        float rScaled = clamp((color.r - params.domainMin.r) * params.scale.r, 0.0, maxIndex);
        float gScaled = clamp((color.g - params.domainMin.g) * params.scale.g, 0.0, maxIndex);
        float bScaled = clamp((color.b - params.domainMin.b) * params.scale.b, 0.0, maxIndex);

        int r0 = int(floor(rScaled));
        int g0 = int(floor(gScaled));
        int b0 = int(floor(bScaled));
        int r1 = min(params.lutSize - 1, r0 + 1);
        int g1 = min(params.lutSize - 1, g0 + 1);
        int b1 = min(params.lutSize - 1, b0 + 1);

        float rFrac = rScaled - float(r0);
        float gFrac = gScaled - float(g0);
        float bFrac = bScaled - float(b0);

        float3 c000 = lutTex.read(uint3(r0, g0, b0)).rgb;
        float3 c100 = lutTex.read(uint3(r1, g0, b0)).rgb;
        float3 c010 = lutTex.read(uint3(r0, g1, b0)).rgb;
        float3 c110 = lutTex.read(uint3(r1, g1, b0)).rgb;
        float3 c001 = lutTex.read(uint3(r0, g0, b1)).rgb;
        float3 c101 = lutTex.read(uint3(r1, g0, b1)).rgb;
        float3 c011 = lutTex.read(uint3(r0, g1, b1)).rgb;
        float3 c111 = lutTex.read(uint3(r1, g1, b1)).rgb;

        float oneMinusR = 1.0 - rFrac;
        float oneMinusG = 1.0 - gFrac;
        float oneMinusB = 1.0 - bFrac;

        float3 c00 = c000 * oneMinusR + c100 * rFrac;
        float3 c01 = c001 * oneMinusR + c101 * rFrac;
        float3 c10 = c010 * oneMinusR + c110 * rFrac;
        float3 c11 = c011 * oneMinusR + c111 * rFrac;

        float3 c0 = c00 * oneMinusG + c10 * gFrac;
        float3 c1 = c01 * oneMinusG + c11 * gFrac;

        float3 lutColor = c0 * oneMinusB + c1 * bFrac;
        float3 mixed = mix(color.rgb, lutColor, params.intensity);
        float4 result = clamp(float4(mixed, color.a), 0.0, 1.0);
        uint4 outputPixel = uint4(round(result * 255.0));
        outputTex.write(outputPixel, gid);
    }
    """

    private static func initialize() {
        initLock.lock()
        defer { initLock.unlock() }
        guard context == nil else { return }

        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            return
        }

        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            guard let function = library.makeFunction(name: "applyLUT") else { return }
            let pipelineState = try device.makeComputePipelineState(function: function)
            context = MetalContext(device: device, commandQueue: commandQueue, pipelineState: pipelineState)
        } catch {
            context = nil
        }
    }

    public static var isAvailable: Bool {
        initialize()
        return context != nil
    }

    public static func apply(
        to image: CGImage,
        lut: LUT3D,
        intensity: Double
    ) -> CGImage? {
        initialize()
        guard let context else { return nil }

        let width = image.width
        let height = image.height
        guard let inputTexture = context.inputTexture(width: width, height: height),
              let outputTexture = context.outputTexture(width: width, height: height),
              let lutTexture = context.lutTexture(for: lut) else {
            return nil
        }

        guard upload(image: image, to: inputTexture) else {
            return nil
        }

        var params = LUTParamsMetal(
            lutSize: Int32(lut.size),
            intensity: Float(intensity),
            domainMin: lut.domainMin,
            scale: SIMD3<Float>(
                (Float(lut.size) - 1) / (lut.domainMax.x - lut.domainMin.x),
                (Float(lut.size) - 1) / (lut.domainMax.y - lut.domainMin.y),
                (Float(lut.size) - 1) / (lut.domainMax.z - lut.domainMin.z)
            )
        )

        guard let commandBuffer = context.commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return nil
        }

        encoder.setComputePipelineState(context.pipelineState)
        encoder.setTexture(inputTexture, index: 0)
        encoder.setTexture(outputTexture, index: 1)
        encoder.setTexture(lutTexture, index: 2)
        encoder.setBytes(&params, length: MemoryLayout<LUTParamsMetal>.stride, index: 0)

        let threadWidth = min(context.pipelineState.threadExecutionWidth, 16)
        let maxThreads = max(1, context.pipelineState.maxTotalThreadsPerThreadgroup / threadWidth)
        let threadHeight = min(maxThreads, 16)
        let threadsPerThreadgroup = MTLSize(width: threadWidth, height: threadHeight, depth: 1)
        let threadgroups = MTLSize(
            width: (width + threadsPerThreadgroup.width - 1) / threadsPerThreadgroup.width,
            height: (height + threadsPerThreadgroup.height - 1) / threadsPerThreadgroup.height,
            depth: 1
        )

        encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        return makeCGImage(from: outputTexture, width: width, height: height)
    }

    private static func upload(image: CGImage, to texture: MTLTexture) -> Bool {
        let width = image.width
        let height = image.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixelData = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return false
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: pixelData,
            bytesPerRow: width * 4
        )
        return true
    }

    private static func makeCGImage(from texture: MTLTexture, width: Int, height: Int) -> CGImage? {
        var pixelData = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(
            &pixelData,
            bytesPerRow: width * 4,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0
        )

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let provider = CGDataProvider(data: Data(pixelData) as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    private final class MetalContext {
        let device: MTLDevice
        let commandQueue: MTLCommandQueue
        let pipelineState: MTLComputePipelineState

        private let cacheLock = NSLock()
        private var inputTextures: [TextureKey: MTLTexture] = [:]
        private var outputTextures: [TextureKey: MTLTexture] = [:]
        private var lutTextures: [LUTCacheKey: MTLTexture] = [:]

        init(device: MTLDevice, commandQueue: MTLCommandQueue, pipelineState: MTLComputePipelineState) {
            self.device = device
            self.commandQueue = commandQueue
            self.pipelineState = pipelineState
        }

        func inputTexture(width: Int, height: Int) -> MTLTexture? {
            cachedTexture(for: TextureKey(width: width, height: height), cache: &inputTextures, usage: .shaderRead)
        }

        func outputTexture(width: Int, height: Int) -> MTLTexture? {
            cachedTexture(for: TextureKey(width: width, height: height), cache: &outputTextures, usage: [.shaderRead, .shaderWrite])
        }

        func lutTexture(for lut: LUT3D) -> MTLTexture? {
            let key = LUTCacheKey(lut: lut)

            cacheLock.lock()
            if let cached = lutTextures[key] {
                cacheLock.unlock()
                return cached
            }
            cacheLock.unlock()

            let descriptor = MTLTextureDescriptor()
            descriptor.textureType = .type3D
            descriptor.pixelFormat = .rgba32Float
            descriptor.width = lut.size
            descriptor.height = lut.size
            descriptor.depth = lut.size
            descriptor.usage = .shaderRead

            guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }

            var rgbaData = [Float](repeating: 0, count: lut.size * lut.size * lut.size * 4)
            for i in 0..<(lut.size * lut.size * lut.size) {
                rgbaData[i * 4] = lut.data[i * 3]
                rgbaData[i * 4 + 1] = lut.data[i * 3 + 1]
                rgbaData[i * 4 + 2] = lut.data[i * 3 + 2]
                rgbaData[i * 4 + 3] = 1.0
            }

            texture.replace(
                region: MTLRegion(
                    origin: MTLOrigin(x: 0, y: 0, z: 0),
                    size: MTLSize(width: lut.size, height: lut.size, depth: lut.size)
                ),
                mipmapLevel: 0,
                slice: 0,
                withBytes: &rgbaData,
                bytesPerRow: lut.size * 4 * MemoryLayout<Float>.size,
                bytesPerImage: lut.size * lut.size * 4 * MemoryLayout<Float>.size
            )

            cacheLock.lock()
            lutTextures[key] = texture
            cacheLock.unlock()
            return texture
        }

        private func cachedTexture(
            for key: TextureKey,
            cache: inout [TextureKey: MTLTexture],
            usage: MTLTextureUsage
        ) -> MTLTexture? {
            cacheLock.lock()
            if let cached = cache[key] {
                cacheLock.unlock()
                return cached
            }
            cacheLock.unlock()

            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Uint,
                width: key.width,
                height: key.height,
                mipmapped: false
            )
            descriptor.usage = usage

            guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }

            cacheLock.lock()
            cache[key] = texture
            cacheLock.unlock()
            return texture
        }
    }

    private struct TextureKey: Hashable {
        let width: Int
        let height: Int
    }

    private struct LUTCacheKey: Hashable {
        let size: Int
        let domainMin: SIMD3<UInt32>
        let domainMax: SIMD3<UInt32>
        let dataHash: Int

        init(lut: LUT3D) {
            size = lut.size
            domainMin = SIMD3<UInt32>(
                lut.domainMin.x.bitPattern,
                lut.domainMin.y.bitPattern,
                lut.domainMin.z.bitPattern
            )
            domainMax = SIMD3<UInt32>(
                lut.domainMax.x.bitPattern,
                lut.domainMax.y.bitPattern,
                lut.domainMax.z.bitPattern
            )
            var hasher = Hasher()
            hasher.combine(size)
            hasher.combine(domainMin.x)
            hasher.combine(domainMin.y)
            hasher.combine(domainMin.z)
            hasher.combine(domainMax.x)
            hasher.combine(domainMax.y)
            hasher.combine(domainMax.z)
            for value in lut.data {
                hasher.combine(value.bitPattern)
            }
            dataHash = hasher.finalize()
        }
    }

    private struct LUTParamsMetal {
        var lutSize: Int32
        var intensity: Float
        var domainMin: SIMD3<Float>
        var scale: SIMD3<Float>
    }
    #else
    public static var isAvailable: Bool { false }
    public static func apply(to image: CGImage, lut: LUT3D, intensity: Double) -> CGImage? { nil }
    #endif
}
