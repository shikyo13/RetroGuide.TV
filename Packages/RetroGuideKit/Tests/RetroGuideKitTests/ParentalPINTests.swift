import XCTest
@testable import RetroGuideKit

final class ParentalPINTests: XCTestCase {
    func testPastedInputKeepsOnlyFourASCIIDigits() {
        XCTAssertEqual(ParentalPIN.sanitized("a0 1\n2-3456"), "0123")
        XCTAssertEqual(ParentalPIN.sanitized("１２٣٤😀12345"), "1234")
        XCTAssertEqual(ParentalPIN.sanitized("0000"), "0000")
    }

    func testSubmittedPINMustBeExactlyFourASCIIDigits() {
        for value in ["", "123", "12345", "1234\n", "12 3", "１２３４", "١٢٣٤", "abcd"] {
            XCTAssertFalse(ParentalPIN.isValid(value), value)
        }
        XCTAssertTrue(ParentalPIN.isValid("0123"))
        XCTAssertTrue(ParentalPIN.isValid("0000"))
    }
}
