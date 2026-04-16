import XCTest
@testable import Framer

final class StyledSliderValueResolverTests: XCTestCase {
    func test_constrain_roundsTypedInputToNearestStepWithinRange() {
        XCTAssertEqual(
            StyledSliderValueResolver.constrain(83, range: 60...100, step: 5),
            85
        )
    }

    func test_constrain_clampsTypedInputBelowRangeMinimum() {
        XCTAssertEqual(
            StyledSliderValueResolver.constrain(58, range: 60...100, step: 5),
            60
        )
    }

    func test_constrain_clampsTypedInputAboveRangeMaximumAfterStepping() {
        XCTAssertEqual(
            StyledSliderValueResolver.constrain(99, range: 0...90, step: 15),
            90
        )
    }
}
