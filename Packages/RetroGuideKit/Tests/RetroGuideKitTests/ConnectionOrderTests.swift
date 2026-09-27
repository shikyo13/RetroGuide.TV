import Foundation
import Testing
@testable import RetroGuideKit

@Suite("Plex connection probing order")
struct ConnectionOrderTests {
    private let home = PlexConnectionCandidate(url: URL(string: "https://10-0-0-2.hash.plex.direct:32400")!, isLocal: true, isRelay: false)
    private let remote = PlexConnectionCandidate(url: URL(string: "https://1-2-3-4.hash.plex.direct:32400")!, isLocal: false, isRelay: false)
    private let relay = PlexConnectionCandidate(url: URL(string: "https://5-6-7-8.hash.plex.direct:8443")!, isLocal: false, isRelay: true)

    private func server(sameNetwork: Bool?) -> PlexServerCandidate {
        PlexServerCandidate(id: "s", name: "Server", isOwned: true, accessToken: "t", connections: [home, remote, relay], isOnSameNetwork: sameNetwork)
    }

    @Test("On the same network or unknown, every address is probed at once")
    func sameNetwork() {
        #expect(PlexConnectionResolver.probeGroups(server(sameNetwork: true)) == [[home, remote, relay]])
        #expect(PlexConnectionResolver.probeGroups(server(sameNetwork: nil)) == [[home, remote, relay]])
    }

    @Test("Away from home, remote addresses go first and home ones last")
    func awayFromHome() {
        #expect(PlexConnectionResolver.probeGroups(server(sameNetwork: false)) == [[remote, relay], [home]])
    }
}
