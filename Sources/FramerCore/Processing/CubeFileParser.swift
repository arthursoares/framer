// Sources/FramerCore/Processing/CubeFileParser.swift
import Foundation

// MARK: - LUT3D

public struct LUT3D: Sendable {
    public let size: Int
    public let data: [Float]
    public let domainMin: SIMD3<Float>
    public let domainMax: SIMD3<Float>

    public init(size: Int, data: [Float], domainMin: SIMD3<Float> = SIMD3(0, 0, 0), domainMax: SIMD3<Float> = SIMD3(1, 1, 1)) {
        self.size = size
        self.data = data
        self.domainMin = domainMin
        self.domainMax = domainMax
    }

    @inline(__always)
    public func apply(r: Float, g: Float, b: Float) -> (Float, Float, Float) {
        let size = Float(self.size)
        let scale = (size - 1) / (domainMax.x - domainMin.x)
        let rScaled = (r - domainMin.x) * scale
        let gScaled = (g - domainMin.y) * scale
        let bScaled = (b - domainMin.z) * scale

        let r0 = max(0, min(Float(size - 1), floor(rScaled)))
        let g0 = max(0, min(Float(size - 1), floor(gScaled)))
        let b0 = max(0, min(Float(size - 1), floor(bScaled)))

        let r1 = min(size - 1, r0 + 1)
        let g1 = min(size - 1, g0 + 1)
        let b1 = min(size - 1, b0 + 1)

        let rFrac = rScaled - r0
        let gFrac = gScaled - g0
        let bFrac = bScaled - b0

        let b0i = Int(b0)
        let g0i = Int(g0)
        let r0i = Int(r0)
        let b1i = Int(b1)
        let g1i = Int(g1)
        let r1i = Int(r1)
        let sizeI = Int(size)
        let sizeSq = sizeI * sizeI

        let idx000 = b0i * sizeSq + g0i * sizeI + r0i
        let idx100 = b0i * sizeSq + g0i * sizeI + r1i
        let idx010 = b0i * sizeSq + g1i * sizeI + r0i
        let idx110 = b0i * sizeSq + g1i * sizeI + r1i
        let idx001 = b1i * sizeSq + g0i * sizeI + r0i
        let idx101 = b1i * sizeSq + g0i * sizeI + r1i
        let idx011 = b1i * sizeSq + g1i * sizeI + r0i
        let idx111 = b1i * sizeSq + g1i * sizeI + r1i

        func getColor(_ idx: Int) -> SIMD3<Float> {
            let base = idx * 3
            return SIMD3(data[base], data[base + 1], data[base + 2])
        }

        let c000 = getColor(idx000)
        let c100 = getColor(idx100)
        let c010 = getColor(idx010)
        let c110 = getColor(idx110)
        let c001 = getColor(idx001)
        let c101 = getColor(idx101)
        let c011 = getColor(idx011)
        let c111 = getColor(idx111)

        let oneMinusRFrac = 1 - rFrac
        let c00 = c000 * oneMinusRFrac + c100 * rFrac
        let c01 = c001 * oneMinusRFrac + c101 * rFrac
        let c10 = c010 * oneMinusRFrac + c110 * rFrac
        let c11 = c011 * oneMinusRFrac + c111 * rFrac

        let oneMinusGFrac = 1 - gFrac
        let c0 = c00 * oneMinusGFrac + c10 * gFrac
        let c1 = c01 * oneMinusGFrac + c11 * gFrac

        let oneMinusBFrac = 1 - bFrac
        let c = c0 * oneMinusBFrac + c1 * bFrac

        return (c.x, c.y, c.z)
    }
}

// MARK: - ParseError

public enum CubeFileParseError: LocalizedError {
    case missingSize
    case invalidSize(Int)
    case insufficientData(expected: Int, got: Int)
    case invalidLine(String)
    case domainOutOfOrder

    public var errorDescription: String? {
        switch self {
        case .missingSize:
            return "LUT file is missing LUT_3D_SIZE directive"
        case .invalidSize(let size):
            return "Invalid LUT_3D_SIZE: \(size) (must be 2–256)"
        case .insufficientData(let expected, let got):
            return "Insufficient data: expected \(expected) triplets, got \(got)"
        case .invalidLine(let line):
            return "Invalid line in LUT file: \(line)"
        case .domainOutOfOrder:
            return "DOMAIN_MIN values must be less than DOMAIN_MAX"
        }
    }
}

// MARK: - CubeFileParser

public enum CubeFileParser {
    public static func parse(from url: URL) throws -> LUT3D {
        let string = try String(contentsOf: url, encoding: .utf8)
        return try parse(string: string)
    }

    public static func parse(string: String) throws -> LUT3D {
        var size: Int?
        var domainMin: SIMD3<Float> = SIMD3(0, 0, 0)
        var domainMax: SIMD3<Float> = SIMD3(1, 1, 1)
        var hasDomainMin = false
        var hasDomainMax = false
        var data: [Float] = []
        data.reserveCapacity(256 * 256 * 256)

        let lines = string.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            if trimmed.hasPrefix("TITLE") {
                continue
            }

            if trimmed.hasPrefix("LUT_3D_SIZE") {
                let parts = trimmed.split(separator: " ")
                if parts.count < 2 {
                    throw CubeFileParseError.missingSize
                }
                guard let parsedSize = Int(parts[1]), parsedSize >= 2, parsedSize <= 256 else {
                    let val = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
                    throw CubeFileParseError.invalidSize(val)
                }
                size = parsedSize
                continue
            }

            if trimmed.hasPrefix("LUT_1D_SIZE") {
                continue
            }

            if trimmed.hasPrefix("DOMAIN_MIN") {
                let parts = trimmed.split(separator: " ")
                guard parts.count >= 4 else {
                    throw CubeFileParseError.invalidLine(trimmed)
                }
                guard let r = Float(parts[1]), let g = Float(parts[2]), let b = Float(parts[3]) else {
                    throw CubeFileParseError.invalidLine(trimmed)
                }
                domainMin = SIMD3(r, g, b)
                hasDomainMin = true
                continue
            }

            if trimmed.hasPrefix("DOMAIN_MAX") {
                let parts = trimmed.split(separator: " ")
                guard parts.count >= 4 else {
                    throw CubeFileParseError.invalidLine(trimmed)
                }
                guard let r = Float(parts[1]), let g = Float(parts[2]), let b = Float(parts[3]) else {
                    throw CubeFileParseError.invalidLine(trimmed)
                }
                domainMax = SIMD3(r, g, b)
                hasDomainMax = true
                continue
            }

            let parts = trimmed.split(separator: " ")
            guard parts.count >= 3 else {
                if !trimmed.isEmpty {
                    throw CubeFileParseError.invalidLine(trimmed)
                }
                continue
            }
            guard let r = Float(parts[0]), let g = Float(parts[1]), let b = Float(parts[2]) else {
                throw CubeFileParseError.invalidLine(trimmed)
            }
            data.append(r)
            data.append(g)
            data.append(b)
        }

        guard let lutSize = size else {
            throw CubeFileParseError.missingSize
        }

        let expected = lutSize * lutSize * lutSize
        guard data.count >= expected * 3 else {
            throw CubeFileParseError.insufficientData(expected: expected, got: data.count / 3)
        }

        if hasDomainMin && hasDomainMax {
            if domainMin.x >= domainMax.x || domainMin.y >= domainMax.y || domainMin.z >= domainMax.z {
                throw CubeFileParseError.domainOutOfOrder
            }
        }

        return LUT3D(size: lutSize, data: Array(data.prefix(expected * 3)), domainMin: domainMin, domainMax: domainMax)
    }
}