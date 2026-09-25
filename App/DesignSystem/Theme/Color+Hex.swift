import SwiftUI

extension Color {
    private enum HexLayout {
        static let rgbDigits = 6
        static let channelMask: UInt64 = 0xFF
        static let redShift: UInt64 = 16
        static let greenShift: UInt64 = 8
        static let channelMax: Double = 255
    }

    /// Creates a color from a `"#RRGGBB"` string. Used only by theme definitions.
    init(hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        if digits.count == HexLayout.rgbDigits {
            Scanner(string: digits).scanHexInt64(&value)
        }
        self.init(
            red: Double((value >> HexLayout.redShift) & HexLayout.channelMask) / HexLayout.channelMax,
            green: Double((value >> HexLayout.greenShift) & HexLayout.channelMask) / HexLayout.channelMax,
            blue: Double(value & HexLayout.channelMask) / HexLayout.channelMax
        )
    }
}
