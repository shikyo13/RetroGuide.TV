import Foundation
import Testing
@testable import RetroGuideCore

@Suite("Core requests")
struct CoreRequestTests {
    private let resources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "../../Packages/RetroGuideKit/Sources/RetroGuideKit/Resources").standardizedFileURL

    private func response(_ core: Core, _ json: String) async throws -> [String: Any] {
        let text = await core.respond(to: json)
        return try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    @Test("A fresh install starts with no servers or channels")
    func startsEmpty() async throws {
        let files = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let core = Core()
        let start = try await response(core, """
            {"method":"start","params":{"filesDirectory":"\(files.path)","resourcesDirectory":"\(resources.path)",
             "installID":"test","deviceName":"Test","appVersion":"1","osVersion":"16","tokens":{}}}
            """)
        #expect(start["ok"] as? Bool == true)
        let result = try #require(start["result"] as? [String: Any])
        #expect((result["servers"] as? [Any])?.isEmpty == true)
        #expect(result["channelCount"] as? Int == 0)
    }

    @Test("An unknown request is answered with an error, not a crash")
    func unknownMethod() async throws {
        let answer = try await response(Core(), #"{"method":"nope","params":{}}"#)
        #expect(answer["ok"] as? Bool == false)
        #expect((answer["error"] as? String)?.contains("nope") == true)
    }
}
