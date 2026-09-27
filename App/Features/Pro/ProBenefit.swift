import Foundation

/// The features RetroGuide Pro adds, as listed on the upgrade page.
struct ProBenefit: Identifiable {
    let id: String
    let systemImage: String
    let title: String
    let detail: String

    static let all: [ProBenefit] = [
        ProBenefit(
            id: "ads",
            systemImage: "nosign",
            title: "No ads",
            detail: "Removes the banner and full-screen ads on iPhone and iPad."
        ),
        ProBenefit(
            id: "servers",
            systemImage: "server.rack",
            title: "Multiple servers",
            detail: "Blend your server and ones shared with you into one lineup."
        ),
        ProBenefit(
            id: "channels",
            systemImage: "plus.rectangle.on.rectangle",
            title: "Unlimited custom channels",
            detail: "Build as many of your own channels as you like."
        ),
        ProBenefit(
            id: "themes",
            systemImage: "paintpalette",
            title: "Every theme",
            detail: "\(ThemeID.allCases.count) looks, from Local Forecast to Teletext."
        ),
        ProBenefit(
            id: "scheduling",
            systemImage: "calendar.badge.clock",
            title: "Schedule controls",
            detail: "Pick each channel's order and start programs on the hour and half hour."
        ),
    ]
}
