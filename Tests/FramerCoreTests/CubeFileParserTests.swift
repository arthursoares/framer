// Tests/FramerCoreTests/CubeFileParserTests.swift
import XCTest
@testable import FramerCore

final class CubeFileParserTests: XCTestCase {

    // MARK: - Valid File Parsing

    func test_cubeParser_validFile() throws {
        let cube = """
        LUT_3D_SIZE 2
        0.0 0.0 0.0
        1.0 0.0 0.0
        0.0 1.0 0.0
        1.0 1.0 0.0
        0.0 0.0 1.0
        1.0 0.0 1.0
        0.0 1.0 1.0
        1.0 1.0 1.0
        """

        let lut = try CubeFileParser.parse(string: cube)
        XCTAssertEqual(lut.size, 2)
        XCTAssertEqual(lut.data.count, 2 * 2 * 2 * 3)
        XCTAssertEqual(lut.domainMin, SIMD3<Float>(0, 0, 0))
        XCTAssertEqual(lut.domainMax, SIMD3<Float>(1, 1, 1))
    }

    func test_cubeParser_withTitle() throws {
        let cube = """
        TITLE "Portra 400"
        LUT_3D_SIZE 2
        0.0 0.0 0.0
        1.0 0.0 0.0
        0.0 1.0 0.0
        1.0 1.0 0.0
        0.0 0.0 1.0
        1.0 0.0 1.0
        0.0 1.0 1.0
        1.0 1.0 1.0
        """

        let lut = try CubeFileParser.parse(string: cube)
        XCTAssertEqual(lut.size, 2)
    }

    func test_cubeParser_withDomainMinMax() throws {
        let cube = """
        TITLE "Cinematic"
        LUT_3D_SIZE 2
        DOMAIN_MIN 0.0 0.0 0.0
        DOMAIN_MAX 2.0 2.0 2.0
        0.0 0.0 0.0
        2.0 0.0 0.0
        0.0 2.0 0.0
        2.0 2.0 0.0
        0.0 0.0 2.0
        2.0 0.0 2.0
        0.0 2.0 2.0
        2.0 2.0 2.0
        """

        let lut = try CubeFileParser.parse(string: cube)
        XCTAssertEqual(lut.size, 2)
        XCTAssertEqual(lut.domainMin, SIMD3<Float>(0, 0, 0))
        XCTAssertEqual(lut.domainMax, SIMD3<Float>(2, 2, 2))
    }

    func test_cubeParser_33size() throws {
        var cube = "LUT_3D_SIZE 3\n"
        let expected = 3 * 3 * 3
        for i in 0..<expected {
            cube += "\(Float(i) * 0.1) \(Float(i) * 0.1) \(Float(i) * 0.1)\n"
        }

        let lut = try CubeFileParser.parse(string: cube)
        XCTAssertEqual(lut.size, 3)
        XCTAssertEqual(lut.data.count, expected * 3)
    }

    // MARK: - Invalid Files

    func test_cubeParser_missingSize() throws {
        let cube = """
        0.0 0.0 0.0
        1.0 0.0 0.0
        """

        do {
            _ = try CubeFileParser.parse(string: cube)
            XCTFail("Expected CubeFileParseError.missingSize")
        } catch let error as CubeFileParseError {
            if case .missingSize = error {
                // expected
            } else {
                XCTFail("Expected .missingSize, got \(error)")
            }
        }
    }

    func test_cubeParser_invalidSize() throws {
        let cube = """
        LUT_3D_SIZE 1
        0.0 0.0 0.0
        """

        do {
            _ = try CubeFileParser.parse(string: cube)
            XCTFail("Expected CubeFileParseError.invalidSize")
        } catch let error as CubeFileParseError {
            if case .invalidSize(let size) = error {
                XCTAssertEqual(size, 1)
            } else {
                XCTFail("Expected .invalidSize, got \(error)")
            }
        }
    }

    func test_cubeParser_sizeTooLarge() throws {
        let cube = """
        LUT_3D_SIZE 257
        0.0 0.0 0.0
        """

        do {
            _ = try CubeFileParser.parse(string: cube)
            XCTFail("Expected CubeFileParseError.invalidSize")
        } catch let error as CubeFileParseError {
            if case .invalidSize(let size) = error {
                XCTAssertEqual(size, 257)
            } else {
                XCTFail("Expected .invalidSize, got \(error)")
            }
        }
    }

    func test_cubeParser_insufficientData() throws {
        let cube = """
        LUT_3D_SIZE 3
        0.0 0.0 0.0
        1.0 0.0 0.0
        """

        do {
            _ = try CubeFileParser.parse(string: cube)
            XCTFail("Expected CubeFileParseError.insufficientData")
        } catch let error as CubeFileParseError {
            if case .insufficientData = error {
                // expected
            } else {
                XCTFail("Expected .insufficientData, got \(error)")
            }
        }
    }

    func test_cubeParser_invalidLine() throws {
        let cube = """
        LUT_3D_SIZE 2
        0.0 0.0
        1.0 0.0 0.0
        """

        do {
            _ = try CubeFileParser.parse(string: cube)
            XCTFail("Expected CubeFileParseError.invalidLine")
        } catch let error as CubeFileParseError {
            if case .invalidLine = error {
                // expected
            } else {
                XCTFail("Expected .invalidLine, got \(error)")
            }
        }
    }

    func test_cubeParser_commentsIgnored() throws {
        let cube = """
        # This is a comment
        TITLE "Test LUT"
        # Another comment
        LUT_3D_SIZE 2
        # Comment before data
        0.0 0.0 0.0
        1.0 0.0 0.0
        0.0 1.0 0.0
        1.0 1.0 0.0
        0.0 0.0 1.0
        1.0 0.0 1.0
        0.0 1.0 1.0
        1.0 1.0 1.0
        """

        let lut = try CubeFileParser.parse(string: cube)
        XCTAssertEqual(lut.size, 2)
        XCTAssertEqual(lut.data.count, 8 * 3)
    }

    func test_cubeParser_hybrid1DAnd3D_skips1DSection() throws {
        let cube = """
        TITLE "Hybrid LUT"
        LUT_1D_SIZE 2
        0.1 0.1 0.1
        0.2 0.2 0.2
        LUT_3D_SIZE 2
        0.0 0.0 0.0
        1.0 0.0 0.0
        0.0 1.0 0.0
        1.0 1.0 0.0
        0.0 0.0 1.0
        1.0 0.0 1.0
        0.0 1.0 1.0
        1.0 1.0 1.0
        """

        let lut = try CubeFileParser.parse(string: cube)
        XCTAssertEqual(lut.size, 2)
        XCTAssertEqual(lut.data[0], 0.0, accuracy: 0.0001)
        XCTAssertEqual(lut.data[1], 0.0, accuracy: 0.0001)
        XCTAssertEqual(lut.data[2], 0.0, accuracy: 0.0001)
    }

    func test_cubeParser_domainOutOfOrder() throws {
        let cube = """
        LUT_3D_SIZE 2
        DOMAIN_MIN 1.0 0.0 0.0
        DOMAIN_MAX 0.0 1.0 1.0
        0.0 0.0 0.0
        1.0 0.0 0.0
        0.0 1.0 0.0
        1.0 1.0 0.0
        0.0 0.0 1.0
        1.0 0.0 1.0
        0.0 1.0 1.0
        1.0 1.0 1.0
        """

        do {
            _ = try CubeFileParser.parse(string: cube)
            XCTFail("Expected CubeFileParseError.domainOutOfOrder")
        } catch let error as CubeFileParseError {
            if case .domainOutOfOrder = error {
                // expected
            } else {
                XCTFail("Expected .domainOutOfOrder, got \(error)")
            }
        }
    }

    // MARK: - LUT3D Trilinear Interpolation

    func test_lut3D_identityInterpolation() throws {
        let lut = LUT3D(
            size: 2,
            data: [
                0, 0, 0,
                1, 0, 0,
                0, 1, 0,
                1, 1, 0,
                0, 0, 1,
                1, 0, 1,
                0, 1, 1,
                1, 1, 1
            ]
        )

        let (r, g, b) = lut.apply(r: 0.5, g: 0.5, b: 0.5)
        XCTAssertEqual(r, 0.5, accuracy: 0.001)
        XCTAssertEqual(g, 0.5, accuracy: 0.001)
        XCTAssertEqual(b, 0.5, accuracy: 0.001)
    }

    func test_lut3D_cornerValues() throws {
        let lut = LUT3D(
            size: 2,
            data: [
                0, 0, 0,
                1, 0, 0,
                0, 1, 0,
                1, 1, 0,
                0, 0, 1,
                1, 0, 1,
                0, 1, 1,
                1, 1, 1
            ]
        )

        let (r0, g0, b0) = lut.apply(r: 0, g: 0, b: 0)
        XCTAssertEqual(r0, 0, accuracy: 0.001)
        XCTAssertEqual(g0, 0, accuracy: 0.001)
        XCTAssertEqual(b0, 0, accuracy: 0.001)

        let (r1, g1, b1) = lut.apply(r: 1, g: 1, b: 1)
        XCTAssertEqual(r1, 1, accuracy: 0.001)
        XCTAssertEqual(g1, 1, accuracy: 0.001)
        XCTAssertEqual(b1, 1, accuracy: 0.001)
    }

    func test_lut3D_clampsBelowDomainMin() throws {
        let lut = LUT3D(
            size: 2,
            data: [
                0.4, 0.4, 0.4,
                1.0, 1.0, 1.0,
                0.4, 0.4, 0.4,
                1.0, 1.0, 1.0,
                0.4, 0.4, 0.4,
                1.0, 1.0, 1.0,
                0.4, 0.4, 0.4,
                1.0, 1.0, 1.0
            ],
            domainMin: SIMD3<Float>(repeating: 0.5),
            domainMax: SIMD3<Float>(repeating: 1.0)
        )

        let (r, g, b) = lut.apply(r: 0.0, g: 0.5, b: 0.5)
        XCTAssertEqual(r, 0.4, accuracy: 0.001)
        XCTAssertEqual(g, 0.4, accuracy: 0.001)
        XCTAssertEqual(b, 0.4, accuracy: 0.001)
    }
}
