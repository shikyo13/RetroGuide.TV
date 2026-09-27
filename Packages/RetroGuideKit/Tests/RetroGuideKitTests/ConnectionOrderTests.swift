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

    @Test("Away but on a VPN, every address is probed at once so home can win")
    func awayOnVPN() {
        #expect(PlexConnectionResolver.probeGroups(server(sameNetwork: false), isVPNActive: true) == [[home, remote, relay]])
    }

    @Test("Prefer home tries home addresses first even when away")
    func preferHome() {
        let settings = ServerConnectionSettings(preference: .preferHome)
        #expect(PlexConnectionResolver.probeGroups(server(sameNetwork: false), settings: settings) == [[home], [remote, relay]])
    }

    @Test("A custom address is tried on its own first")
    func customFirst() throws {
        let custom = try #require(URL(string: "https://100-101-102-103.hash.plex.direct:32400"))
        let settings = ServerConnectionSettings(preference: .custom, customAddress: custom)
        let groups = PlexConnectionResolver.probeGroups(server(sameNetwork: true), settings: settings)
        #expect(groups.first?.map(\.url) == [custom])
        #expect(groups.first?.first?.isLocal == true)
        #expect(groups.dropFirst().first == [home, remote, relay])
    }

    @Test("Ranking: custom beats home/VPN beats internet")
    func ranking() throws {
        let custom = try #require(URL(string: "https://100-101-102-103.hash.plex.direct:32400"))
        let settings = ServerConnectionSettings(preference: .custom, customAddress: custom)
        #expect(PlexConnectionResolver.rank(of: custom, settings: settings) < PlexConnectionResolver.rank(of: home.url, settings: settings))
        #expect(PlexConnectionResolver.rank(of: home.url, settings: settings) < PlexConnectionResolver.rank(of: remote.url, settings: settings))
        #expect(PlexConnectionResolver.bestPossibleRank(for: .automatic) == PlexConnectionResolver.rank(of: home.url, settings: .automatic))
    }
}

@Suite("Custom server address")
struct CustomAddressTests {
    private let server = URL(string: "https://10-10-1-25.abc123.plex.direct:32400")

    @Test("A bare IP becomes the server's plex.direct address with the default port")
    func bareIP() {
        #expect(PlexCustomAddress.url(from: "100.101.102.103", serverURL: server)?.absoluteString == "https://100-101-102-103.abc123.plex.direct:32400")
    }

    @Test("An IP with a port keeps the port")
    func ipWithPort() {
        #expect(PlexCustomAddress.url(from: " 100.101.102.103:64800 ", serverURL: server)?.absoluteString == "https://100-101-102-103.abc123.plex.direct:64800")
    }

    @Test("Without a known plex.direct hash, a bare IP uses plain HTTP")
    func ipWithoutHash() {
        #expect(PlexCustomAddress.url(from: "100.101.102.103", serverURL: nil)?.absoluteString == "http://100.101.102.103:32400")
    }

    @Test("Full URLs are used as typed; hostnames get HTTPS and the default port")
    func urlsAndHosts() {
        #expect(PlexCustomAddress.url(from: "http://komputer:32400", serverURL: server)?.absoluteString == "http://komputer:32400")
        #expect(PlexCustomAddress.url(from: "komputer.tail1234.ts.net", serverURL: server)?.absoluteString == "https://komputer.tail1234.ts.net:32400")
        #expect(PlexCustomAddress.url(from: "   ", serverURL: server) == nil)
    }

    @Test("Routes: home, VPN or internet")
    func routes() {
        #expect(ConnectionRoute(URL(string: "https://10-10-1-25.abc.plex.direct:32400")!) == .home)
        #expect(ConnectionRoute(URL(string: "https://100-90-76-43.abc.plex.direct:32400")!) == .vpn)
        #expect(ConnectionRoute(URL(string: "https://136-32-243-210.abc.plex.direct:64800")!) == .internet)
    }

    @Test("Tailscale addresses count as VPN")
    func tailscaleDetection() {
        #expect(NetworkLocation.isLikelyVPN(URL(string: "https://100-101-102-103.abc.plex.direct:32400")!))
        #expect(NetworkLocation.isLikelyVPN(URL(string: "https://komputer.tail1234.ts.net:32400")!))
        #expect(!NetworkLocation.isLikelyVPN(URL(string: "https://136-32-243-210.abc.plex.direct:64800")!))
    }
}
