// Sources/FramerCore/Processing/LUTRenderer.swift
import Foundation
import CoreGraphics
import Accelerate

// MARK: - LUTRenderer

public enum LUTRenderer {
    public static func apply(
        to image: CGImage,
        lut: LUT3D,
        intensity: Double,
        previewBaseDimension: Int? = nil
    ) throws -> CGImage {
        // Metal temporarily disabled until shader compilation is fixed
        // if let gpuResult = LUTMetalRenderer.apply(to: image, lut: lut, intensity: intensity) {
        //     return gpuResult
        // }

        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        let scale: Int
        if let previewBase = previewBaseDimension {
            let currentMax = max(width, height)
            scale = max(1, min(8, Int(round(Double(currentMax) / Double(previewBase)))))
        } else {
            scale = 1
        }

        let workW: Int
        let workH: Int
        if scale > 1 {
            workW = max(1, width / scale)
            workH = max(1, height / scale)
        } else {
            workW = width
            workH = height
        }

        guard let ctx = CGContext(
            data: nil, width: workW, height: workH,
            bitsPerComponent: 8, bytesPerRow: workW * 4,
            space: colorSpace, bitmapInfo: bitmapInfo
        ) else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        ctx.interpolationQuality = scale > 1 ? .high : .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: workW, height: workH))

        guard let data = ctx.data else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }
        let pixels = data.bindMemory(to: UInt8.self, capacity: workW * workH * 4)

        let lutSize = lut.size
        let lutData = lut.data
        let domainMin = lut.domainMin
        let domainMax = lut.domainMax
        let scaleX = (Float(lutSize) - 1) / (domainMax.x - domainMin.x)
        let scaleY = (Float(lutSize) - 1) / (domainMax.y - domainMin.y)
        let scaleZ = (Float(lutSize) - 1) / (domainMax.z - domainMin.z)
        let lutSizeI = Int32(lutSize)
        let lutSizeSq = Int32(lutSize * lutSize)

        let count = workW * workH
        let intensityFloat = Float(intensity)

        if intensityFloat >= 0.999 {
            applyLUTFull(
                pixels: pixels, count: count,
                lutData: lutData,
                lutSize: lutSize, lutSizeI: lutSizeI, lutSizeSq: lutSizeSq,
                domainMin: domainMin, domainMax: domainMax,
                scaleX: scaleX, scaleY: scaleY, scaleZ: scaleZ
            )
        } else if intensityFloat <= 0.001 {
            // Intensity 0: return original (no-op)
        } else {
            applyLUTBlended(
                pixels: pixels, count: count,
                lutData: lutData,
                lutSize: lutSize, lutSizeI: lutSizeI, lutSizeSq: lutSizeSq,
                domainMin: domainMin, domainMax: domainMax,
                scaleX: scaleX, scaleY: scaleY, scaleZ: scaleZ,
                intensity: intensityFloat
            )
        }

        guard let result = ctx.makeImage() else {
            throw FramerError.invalidImage(URL(fileURLWithPath: ""))
        }

        if scale > 1 {
            guard let outCtx = CGContext(
                data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: colorSpace, bitmapInfo: bitmapInfo
            ) else {
                throw FramerError.invalidImage(URL(fileURLWithPath: ""))
            }
            outCtx.interpolationQuality = .none
            outCtx.draw(result, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard let upscaled = outCtx.makeImage() else {
                throw FramerError.invalidImage(URL(fileURLWithPath: ""))
            }
            return upscaled
        }

        return result
    }

    private static func applyLUTFull(
        pixels: UnsafeMutablePointer<UInt8>,
        count: Int,
        lutData: [Float],
        lutSize: Int,
        lutSizeI: Int32,
        lutSizeSq: Int32,
        domainMin: SIMD3<Float>,
        domainMax: SIMD3<Float>,
        scaleX: Float,
        scaleY: Float,
        scaleZ: Float
    ) {
        for i in 0..<count {
            let idx = i * 4

            let rIn = Float(pixels[idx]) / 255.0
            let gIn = Float(pixels[idx + 1]) / 255.0
            let bIn = Float(pixels[idx + 2]) / 255.0

            let rScaled = (rIn - domainMin.x) * scaleX
            let gScaled = (gIn - domainMin.y) * scaleY
            let bScaled = (bIn - domainMin.z) * scaleZ

            let r0 = max(0, min(Float(lutSize - 1), floor(rScaled)))
            let g0 = max(0, min(Float(lutSize - 1), floor(gScaled)))
            let b0 = max(0, min(Float(lutSize - 1), floor(bScaled)))

            let r1 = min(Float(lutSize - 1), r0 + 1)
            let g1 = min(Float(lutSize - 1), g0 + 1)
            let b1 = min(Float(lutSize - 1), b0 + 1)

            let rFrac = rScaled - r0
            let gFrac = gScaled - g0
            let bFrac = bScaled - b0

            let b0i = Int32(b0)
            let g0i = Int32(g0)
            let r0i = Int32(r0)
            let b1i = Int32(b1)
            let g1i = Int32(g1)
            let r1i = Int32(r1)

            let idx000 = b0i * lutSizeSq + g0i * lutSizeI + r0i
            let idx100 = b0i * lutSizeSq + g0i * lutSizeI + r1i
            let idx010 = b0i * lutSizeSq + g1i * lutSizeI + r0i
            let idx110 = b0i * lutSizeSq + g1i * lutSizeI + r1i
            let idx001 = b1i * lutSizeSq + g0i * lutSizeI + r0i
            let idx101 = b1i * lutSizeSq + g0i * lutSizeI + r1i
            let idx011 = b1i * lutSizeSq + g1i * lutSizeI + r0i
            let idx111 = b1i * lutSizeSq + g1i * lutSizeI + r1i

            let oneMinusR = 1.0 - rFrac
            let oneMinusG = 1.0 - gFrac
            let oneMinusB = 1.0 - bFrac

            let c000R = lutData[Int(idx000) * 3]
            let c000G = lutData[Int(idx000) * 3 + 1]
            let c000B = lutData[Int(idx000) * 3 + 2]

            let c100R = lutData[Int(idx100) * 3]
            let c100G = lutData[Int(idx100) * 3 + 1]
            let c100B = lutData[Int(idx100) * 3 + 2]

            let c010R = lutData[Int(idx010) * 3]
            let c010G = lutData[Int(idx010) * 3 + 1]
            let c010B = lutData[Int(idx010) * 3 + 2]

            let c110R = lutData[Int(idx110) * 3]
            let c110G = lutData[Int(idx110) * 3 + 1]
            let c110B = lutData[Int(idx110) * 3 + 2]

            let c001R = lutData[Int(idx001) * 3]
            let c001G = lutData[Int(idx001) * 3 + 1]
            let c001B = lutData[Int(idx001) * 3 + 2]

            let c101R = lutData[Int(idx101) * 3]
            let c101G = lutData[Int(idx101) * 3 + 1]
            let c101B = lutData[Int(idx101) * 3 + 2]

            let c011R = lutData[Int(idx011) * 3]
            let c011G = lutData[Int(idx011) * 3 + 1]
            let c011B = lutData[Int(idx011) * 3 + 2]

            let c111R = lutData[Int(idx111) * 3]
            let c111G = lutData[Int(idx111) * 3 + 1]
            let c111B = lutData[Int(idx111) * 3 + 2]

            let c00R = c000R * oneMinusR + c100R * rFrac
            let c00G = c000G * oneMinusR + c100G * rFrac
            let c00B = c000B * oneMinusR + c100B * rFrac

            let c01R = c001R * oneMinusR + c101R * rFrac
            let c01G = c001G * oneMinusR + c101G * rFrac
            let c01B = c001B * oneMinusR + c101B * rFrac

            let c10R = c010R * oneMinusR + c110R * rFrac
            let c10G = c010G * oneMinusR + c110G * rFrac
            let c10B = c010B * oneMinusR + c110B * rFrac

            let c11R = c011R * oneMinusR + c111R * rFrac
            let c11G = c011G * oneMinusR + c111G * rFrac
            let c11B = c011B * oneMinusR + c111B * rFrac

            let c0R = c00R * oneMinusG + c10R * gFrac
            let c0G = c00G * oneMinusG + c10G * gFrac
            let c0B = c00B * oneMinusG + c10B * gFrac

            let c1R = c01R * oneMinusG + c11R * gFrac
            let c1G = c01G * oneMinusG + c11G * gFrac
            let c1B = c01B * oneMinusG + c11B * gFrac

            let cR = c0R * oneMinusB + c1R * bFrac
            let cG = c0G * oneMinusB + c1G * bFrac
            let cB = c0B * oneMinusB + c1B * bFrac

            pixels[idx] = UInt8(max(0, min(255, Int(round(cR * 255.0)))))
            pixels[idx + 1] = UInt8(max(0, min(255, Int(round(cG * 255.0)))))
            pixels[idx + 2] = UInt8(max(0, min(255, Int(round(cB * 255.0)))))
        }
    }

    private static func applyLUTBlended(
        pixels: UnsafeMutablePointer<UInt8>,
        count: Int,
        lutData: [Float],
        lutSize: Int,
        lutSizeI: Int32,
        lutSizeSq: Int32,
        domainMin: SIMD3<Float>,
        domainMax: SIMD3<Float>,
        scaleX: Float,
        scaleY: Float,
        scaleZ: Float,
        intensity: Float
    ) {
        for i in 0..<count {
            let idx = i * 4

            let rIn = Float(pixels[idx]) / 255.0
            let gIn = Float(pixels[idx + 1]) / 255.0
            let bIn = Float(pixels[idx + 2]) / 255.0

            let rScaled = (rIn - domainMin.x) * scaleX
            let gScaled = (gIn - domainMin.y) * scaleY
            let bScaled = (bIn - domainMin.z) * scaleZ

            let r0 = max(0, min(Float(lutSize - 1), floor(rScaled)))
            let g0 = max(0, min(Float(lutSize - 1), floor(gScaled)))
            let b0 = max(0, min(Float(lutSize - 1), floor(bScaled)))

            let r1 = min(Float(lutSize - 1), r0 + 1)
            let g1 = min(Float(lutSize - 1), g0 + 1)
            let b1 = min(Float(lutSize - 1), b0 + 1)

            let rFrac = rScaled - r0
            let gFrac = gScaled - g0
            let bFrac = bScaled - b0

            let b0i = Int32(b0)
            let g0i = Int32(g0)
            let r0i = Int32(r0)
            let b1i = Int32(b1)
            let g1i = Int32(g1)
            let r1i = Int32(r1)

            let idx000 = b0i * lutSizeSq + g0i * lutSizeI + r0i
            let idx100 = b0i * lutSizeSq + g0i * lutSizeI + r1i
            let idx010 = b0i * lutSizeSq + g1i * lutSizeI + r0i
            let idx110 = b0i * lutSizeSq + g1i * lutSizeI + r1i
            let idx001 = b1i * lutSizeSq + g0i * lutSizeI + r0i
            let idx101 = b1i * lutSizeSq + g0i * lutSizeI + r1i
            let idx011 = b1i * lutSizeSq + g1i * lutSizeI + r0i
            let idx111 = b1i * lutSizeSq + g1i * lutSizeI + r1i

            let oneMinusR = 1.0 - rFrac
            let oneMinusG = 1.0 - gFrac
            let oneMinusB = 1.0 - bFrac

            let c000R = lutData[Int(idx000) * 3]
            let c000G = lutData[Int(idx000) * 3 + 1]
            let c000B = lutData[Int(idx000) * 3 + 2]

            let c100R = lutData[Int(idx100) * 3]
            let c100G = lutData[Int(idx100) * 3 + 1]
            let c100B = lutData[Int(idx100) * 3 + 2]

            let c010R = lutData[Int(idx010) * 3]
            let c010G = lutData[Int(idx010) * 3 + 1]
            let c010B = lutData[Int(idx010) * 3 + 2]

            let c110R = lutData[Int(idx110) * 3]
            let c110G = lutData[Int(idx110) * 3 + 1]
            let c110B = lutData[Int(idx110) * 3 + 2]

            let c001R = lutData[Int(idx001) * 3]
            let c001G = lutData[Int(idx001) * 3 + 1]
            let c001B = lutData[Int(idx001) * 3 + 2]

            let c101R = lutData[Int(idx101) * 3]
            let c101G = lutData[Int(idx101) * 3 + 1]
            let c101B = lutData[Int(idx101) * 3 + 2]

            let c011R = lutData[Int(idx011) * 3]
            let c011G = lutData[Int(idx011) * 3 + 1]
            let c011B = lutData[Int(idx011) * 3 + 2]

            let c111R = lutData[Int(idx111) * 3]
            let c111G = lutData[Int(idx111) * 3 + 1]
            let c111B = lutData[Int(idx111) * 3 + 2]

            let c00R = c000R * oneMinusR + c100R * rFrac
            let c00G = c000G * oneMinusR + c100G * rFrac
            let c00B = c000B * oneMinusR + c100B * rFrac

            let c01R = c001R * oneMinusR + c101R * rFrac
            let c01G = c001G * oneMinusR + c101G * rFrac
            let c01B = c001B * oneMinusR + c101B * rFrac

            let c10R = c010R * oneMinusR + c110R * rFrac
            let c10G = c010G * oneMinusR + c110G * rFrac
            let c10B = c010B * oneMinusR + c110B * rFrac

            let c11R = c011R * oneMinusR + c111R * rFrac
            let c11G = c011G * oneMinusR + c111G * rFrac
            let c11B = c011B * oneMinusR + c111B * rFrac

            let c0R = c00R * oneMinusG + c10R * gFrac
            let c0G = c00G * oneMinusG + c10G * gFrac
            let c0B = c00B * oneMinusG + c10B * gFrac

            let c1R = c01R * oneMinusG + c11R * gFrac
            let c1G = c01G * oneMinusG + c11G * gFrac
            let c1B = c01B * oneMinusG + c11B * gFrac

            let cR = c0R * oneMinusB + c1R * bFrac
            let cG = c0G * oneMinusB + c1G * bFrac
            let cB = c0B * oneMinusB + c1B * bFrac

            let oneMinusIntensity = 1.0 - intensity
            let finalR = rIn * oneMinusIntensity + cR * intensity
            let finalG = gIn * oneMinusIntensity + cG * intensity
            let finalB = bIn * oneMinusIntensity + cB * intensity

            pixels[idx] = UInt8(max(0, min(255, Int(round(finalR * 255.0)))))
            pixels[idx + 1] = UInt8(max(0, min(255, Int(round(finalG * 255.0)))))
            pixels[idx + 2] = UInt8(max(0, min(255, Int(round(finalB * 255.0)))))
        }
    }
}
