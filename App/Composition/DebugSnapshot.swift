#if DEBUG && os(iOS)
import Foundation
import UIKit

/// Development aid for testing on a physical iPhone or iPad: when the Darwin
/// notification below is posted to the device (`xcrun devicectl device
/// notification post --name …`), the app saves a PNG of its window to its
/// Documents folder, where `devicectl device copy from` can fetch it.
enum DebugSnapshot {
    static let notificationName = "com.adamhunt.retroguide.debug.snapshot"
    static let fileName = "debug-snapshot.png"

    /// Starts listening. Call once at launch.
    static func install() {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            { _, _, _, _, _ in
                Task { @MainActor in DebugSnapshot.capture() }
            },
            notificationName as CFString,
            nil,
            .deliverImmediately
        )
    }

    @MainActor
    private static func capture() {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        guard let window = windows.first(where: \.isKeyWindow) ?? windows.first,
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        else { return }
        let image = UIGraphicsImageRenderer(bounds: window.bounds).pngData { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
        try? image.write(to: documents.appendingPathComponent(fileName), options: .atomic)
    }
}
#endif
