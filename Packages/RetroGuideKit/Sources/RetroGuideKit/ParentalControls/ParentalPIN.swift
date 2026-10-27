/// The same ASCII-digit rules apply to typed, pasted and submitted PINs.
public enum ParentalPIN {
    public static let length = 4

    public static func sanitized(_ input: String) -> String {
        String(input.filter { $0.isASCII && $0.isNumber }.prefix(length))
    }

    public static func isValid(_ input: String) -> Bool {
        input.count == length && input.allSatisfy { $0.isASCII && $0.isNumber }
    }
}
