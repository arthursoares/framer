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
        float3 scale;
    };

    kernel void applyLUT(
        texture2d<float, access::read> inputTex [[texture(0)]],
        texture2d<float, access::write> outputTex [[texture(1)]],
        texture3d<float, access::read> lutTex [[texture(2)]],
        constant LUTParams& params [[buffer(0)]],
        uint2 gid [[thread_position_in_grid]]
    ) {
        if (gid.x >= inputTex.get_width() || gid.y >= inputTex.get_height()) return;

        float4 color = inputTex.read(gid);
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
            scale: SIMD3<Float>(
                (Float(lutSize) - 1) / (lut.domainMax.x - lut.domainMin.x),
                (Float(lutSize) - 1) / (lut.domainMax.y - lut.domainMin.y),
                (Float(lutSize) - 1) / (lut.domainMax.z - lut.domainMin.z)
            )
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
        var bytePixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &bytePixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var pixelData = [Float](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            let src = i * 4
            let dst = i * 4
            pixelData[dst] = Float(bytePixels[src]) / 255.0
            pixelData[dst + 1] = Float(bytePixels[src + 1]) / 255.0
            pixelData[dst + 2] = Float(bytePixels[src + 2]) / 255.0
            pixelData[dst + 3] = Float(bytePixels[src + 3]) / 255.0
        }

        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: pixelData,
            bytesPerRow: width * 4 * MemoryLayout<Float>.size
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
        descriptor.pixelFormat = .rgba32Float
        descriptor.width = size
        descriptor.height = size
        descriptor.depth = size
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared

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
        var floatData = [Float](repeating: 0, count: width * height * 4)
        texture.getBytes(
            &floatData,
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0
        )

        var pixelData = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            let src = i * 4
            let dst = i * 4
            pixelData[dst] = UInt8(max(0, min(255, Int(round(floatData[src] * 255.0)))))
            pixelData[dst + 1] = UInt8(max(0, min(255, Int(round(floatData[src + 1] * 255.0)))))
            pixelData[dst + 2] = UInt8(max(0, min(255, Int(round(floatData[src + 2] * 255.0)))))
            pixelData[dst + 3] = UInt8(max(0, min(255, Int(round(floatData[src + 3] * 255.0)))))
        }

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
        var scale: SIMD3<Float>
    }
    #else
    public static var isAvailable: Bool { false }
    public static func apply(to image: CGImage, lut: LUT3D, intensity: Double) -> CGImage? { nil }
    #endif
}
