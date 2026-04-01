// Sources/FramerCore/Processing/LUTMetalRenderer.swift
import Foundation
import Metal
import CoreGraphics

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - LUTMetalRenderer

public enum LUTMetalRenderer {
    #if canImport(Metal)
    private static var device: MTLDevice?
    private static var commandQueue: MTLCommandQueue?
    private static var pipelineState: MTLComputePipelineState?
    private static let initLock = NSLock()

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct LUTParams {
        int lutSize;
        float intensity;
        float3 domainMin;
        float3 domainMax;
        float scale;
    };

    constant sampler lutSampler(filter::linear, address::clamp_to_edge);

    kernel void applyLUT(
        texture2d<float, access::read> inputTex [[texture(0)]],
        texture2d<float, access::write> outputTex [[texture(1)]],
        texture3d<float, access::sample> lutTex [[texture(2)]],
        constant LUTParams& params [[buffer(0)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= inputTex.get_width() || gid.y >= inputTex.get_height()) return;

        float4 color = inputTex.read(gid);

        float3 uvw;
        uvw.r = (color.r - params.domainMin.r) * params.scale;
        uvw.g = (color.g - params.domainMin.g) * params.scale;
        uvw.b = (color.b - params.domainMin.b) * params.scale;

        float3 lutColor = lutTex.sample(lutSampler, uvw).rgb;

        float3 result = mix(color.rgb, lutColor, params.intensity);
        outputTex.write(float4(result, color.a), gid);
    }
    """

    private static func initialize() {
        initLock.lock()
        defer { initLock.unlock() }
        guard pipelineState == nil else { return }

        guard let d = MTLCreateSystemDefaultDevice() else { return }
        device = d
        commandQueue = d.makeCommandQueue()

        do {
            let library = try d.makeLibrary(source: shaderSource, options: nil)
            guard let function = library.makeFunction(name: "applyLUT") else { return }
            pipelineState = try d.makeComputePipelineState(function: function)
        } catch {
            pipelineState = nil
        }
    }

    public static var isAvailable: Bool {
        initialize()
        return pipelineState != nil
    }

    public static func apply(
        to image: CGImage,
        lut: LUT3D,
        intensity: Double
    ) -> CGImage? {
        guard isAvailable,
              let device = device,
              let commandQueue = commandQueue,
              let pipelineState = pipelineState else { return nil }

        let width = image.width
        let height = image.height
        let lutSize = lut.size

        guard let inputTex = createInputTexture(from: image, device: device),
              let outputTex = createOutputTexture(width: width, height: height, device: device),
              let lutTex = createLUTTexture(lutData: lut.data, size: lutSize, device: device) else {
            return nil
        }

        var params = LUTParamsMetal(
            lutSize: Int32(lutSize),
            intensity: Float(intensity),
            domainMin: lut.domainMin,
            domainMax: lut.domainMax,
            scale: (Float(lutSize) - 1) / (lut.domainMax.x - lut.domainMin.x)
        )

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else { return nil }

        computeEncoder.setComputePipelineState(pipelineState)
        computeEncoder.setTexture(inputTex, index: 0)
        computeEncoder.setTexture(outputTex, index: 1)
        computeEncoder.setTexture(lutTex, index: 2)
        computeEncoder.setBytes(&params, length: MemoryLayout<LUTParamsMetal>.stride, index: 0)

        let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadGroups = MTLSize(
            width: (width + threadGroupSize.width - 1) / threadGroupSize.width,
            height: (height + threadGroupSize.height - 1) / threadGroupSize.height,
            depth: 1
        )
        computeEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        computeEncoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        return makeCGImage(from: outputTex, width: width, height: height)
    }

    private static func createInputTexture(from image: CGImage, device: MTLDevice) -> MTLTexture? {
        let width = image.width
        let height = image.height
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixelData = [Float](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 32,
            bytesPerRow: width * 16,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: pixelData,
            bytesPerRow: width * 16
        )
        return texture
    }

    private static func createOutputTexture(width: Int, height: Int, device: MTLDevice) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderWrite, .shaderRead]
        return device.makeTexture(descriptor: descriptor)
    }

    private static func createLUTTexture(lutData: [Float], size: Int, device: MTLDevice) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = MTLTextureType.type3D
        descriptor.pixelFormat = MTLPixelFormat.rgba32Float
        descriptor.width = size
        descriptor.height = size
        descriptor.depth = size
        descriptor.usage = .shaderRead
        descriptor.storageMode = .managed

        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }

        var rgbaData = [Float](repeating: 0, count: size * size * size * 4)
        for i in 0..<(size * size * size) {
            rgbaData[i * 4] = lutData[i * 3]
            rgbaData[i * 4 + 1] = lutData[i * 3 + 1]
            rgbaData[i * 4 + 2] = lutData[i * 3 + 2]
            rgbaData[i * 4 + 3] = 1.0
        }

        texture.replace(
            region: MTLRegion(
                origin: MTLOrigin(x: 0, y: 0, z: 0),
                size: MTLSize(width: size, height: size, depth: size)
            ),
            mipmapLevel: 0,
            slice: 0,
            withBytes: &rgbaData,
            bytesPerRow: size * 4 * MemoryLayout<Float>.size,
            bytesPerImage: size * size * 4 * MemoryLayout<Float>.size
        )
        return texture
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

    private struct LUTParamsMetal {
        var lutSize: Int32
        var intensity: Float
        var domainMin: SIMD3<Float>
        var domainMax: SIMD3<Float>
        var scale: Float
    }
    #else
    public static var isAvailable: Bool { false }
    public static func apply(to image: CGImage, lut: LUT3D, intensity: Double) -> CGImage? { nil }
    #endif
}
