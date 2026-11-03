import Foundation
import Testing
@testable import RetroGuideKit

@Suite("Interstitial freshness and recovery")
struct InterstitialLoadPolicyTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("An early preload is refreshed before a 90-minute viewing break")
    func freshness() {
        var policy = InterstitialLoadPolicy()
        #expect(policy.shouldLoad(at: start))
        policy.loaded(at: start)
        #expect(!policy.shouldLoad(at: start.addingTimeInterval(54 * 60)))
        #expect(policy.shouldLoad(at: start.addingTimeInterval(55 * 60)))
        #expect(!policy.isFresh(at: start.addingTimeInterval(90 * 60)))
        policy.loaded(at: start.addingTimeInterval(55 * 60))
        #expect(policy.isFresh(at: start.addingTimeInterval(90 * 60)))
    }

    @Test("An offline session backs off, stays bounded, and recovers")
    func retries() {
        var policy = InterstitialLoadPolicy()
        var time = start
        for delay: TimeInterval in [60, 120, 240, 480, 900, 900, 900] {
            policy.failed(at: time)
            #expect(!policy.shouldLoad(at: time.addingTimeInterval(delay - 1)))
            time.addTimeInterval(delay)
            #expect(policy.shouldLoad(at: time))
        }
        policy.loaded(at: time)
        policy.discard()
        policy.failed(at: time)
        #expect(policy.shouldLoad(at: time.addingTimeInterval(60)))
    }

    @Test("Discarding a failed ad does not bypass its retry delay")
    func failureRemainsThrottled() {
        var policy = InterstitialLoadPolicy()
        policy.failed(at: start)
        policy.discard()
        #expect(!policy.shouldLoad(at: start))
        #expect(policy.shouldLoad(at: start.addingTimeInterval(60)))
    }

    @Test("A backwards clock change cannot make an ad fresh indefinitely")
    func clockChange() {
        var policy = InterstitialLoadPolicy()
        policy.loaded(at: start)
        #expect(!policy.isFresh(at: start.addingTimeInterval(-1)))
        #expect(policy.shouldLoad(at: start.addingTimeInterval(-1)))
    }
}
