import Foundation

/// Picks a show's TV networks out of Jellyfin's studios.
///
/// Jellyfin's metadata lists a show's networks first and its production
/// companies after them ("FOX, Netflix, Imagine Television Studios, 20th
/// Century Fox Television"), without saying where one ends. A studio that
/// comes first for some show in the library is taken to be a network; each
/// show's networks are the run of those at the front of its list. So
/// companies don't become network channels.
struct JellyfinNetworks {
    private let networks: Set<String>

    init(shows: [JellyfinItem]) {
        networks = Set(shows.compactMap { $0.studios?.first?.name })
    }

    func networks(of show: JellyfinItem?) -> [String] {
        Array((show?.studios ?? []).map(\.name).prefix { networks.contains($0) })
    }
}
