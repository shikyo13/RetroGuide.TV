import Foundation

/// The features RetroGuide Pro adds, as listed on the upgrade page.
struct ProBenefit: Identifiable {
    let id: String
    let systemImage: String
    let title: String
    let detail: String

    static let all: [ProBenefit] = [
        ProBenefit(id: "favorites", systemImage: "star", title: String(localized: "Favorite channels"), detail: String(localized: "Star your channels and browse or surf just your Favorites.")),
        ProBenefit(id: "reminders", systemImage: "bell", title: String(localized: "Program reminders"), detail: String(localized: "Choose upcoming airings and get a reminder when they start.")),
        ProBenefit(id: "widgets", systemImage: "square.grid.2x2", title: String(localized: "Personal widgets"), detail: String(localized: "Use Favorites, select channels or pin one channel in What's On.")),
        ProBenefit(
            id: "ads",
            systemImage: "nosign",
            title: String(localized: "No ads"),
            detail: String(localized: "Removes the banner and full-screen ads on iPhone and iPad.")
        ),
        ProBenefit(
            id: "servers",
            systemImage: "server.rack",
            title: String(localized: "Multiple servers"),
            detail: String(localized: "Blend your server and ones shared with you into one lineup.")
        ),
        ProBenefit(
            id: "channels",
            systemImage: "plus.rectangle.on.rectangle",
            title: String(localized: "Unlimited custom channels"),
            detail: String(localized: "Build as many of your own channels as you like.")
        ),
        ProBenefit(
            id: "themes",
            systemImage: "paintpalette",
            title: String(localized: "Every theme"),
            detail: String(localized: "\(ThemeID.allCases.count) looks, from Local Forecast to Teletext.")
        ),
        ProBenefit(
            id: "scheduling",
            systemImage: "calendar.badge.clock",
            title: String(localized: "Schedule controls"),
            detail: String(localized: "Pick each channel's order and start programs on the hour and half hour.")
        ),
    ]
}
