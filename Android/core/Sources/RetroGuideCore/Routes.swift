import Foundation
import RetroGuideKit

/// Every request the core answers, by method name.
enum Routes {
    typealias Route = @Sendable (CoreState, Data) async throws -> AnyEncodable

    static let table: [String: Route] = [
        "start": route(StartParams.self) { state, params in try await state.start(params) },
        "servers": route { state in await state.serverList() },
        "server.remove": route(ServerParams.self) { state, params in await state.removeServer(params.serverID) },
        "server.addDevelopment": route(DevelopmentServerParams.self) { state, params in try await state.addDevelopmentServer(params) },
        "libraries": route(ServerParams.self) { state, params in try await state.libraries(serverID: params.serverID) },
        "libraries.select": route(LibrarySelectionParams.self) { state, params in await state.selectLibraries(params) },

        "plex.linkCode": route { state in try await state.plexLinkCode() },
        "plex.checkLink": route(PlexLinkParams.self) { state, params in try await state.checkPlexLink(id: params.id) },
        "plex.servers": route { state in try await state.plexServers() },
        "plex.addServers": route(PlexAddParams.self) { state, params in try await state.addPlexServers(ids: params.ids) },

        "jellyfin.find": route(JellyfinFindParams.self) { state, params in try await state.findJellyfin(address: params.address) },
        "jellyfin.quickConnect": route { state in try await state.startQuickConnect() },
        "jellyfin.checkQuickConnect": route { state in try await state.checkQuickConnect() },
        "jellyfin.signIn": route(JellyfinSignInParams.self) { state, params in try await state.signInJellyfin(params) },

        "refresh": route { state in try await state.refresh() },
        "progress": route { state in await state.loadProgress() },
        "channels": route { state in await state.channelList() },
        "guide": route(GuideParams.self) { state, params in await state.guide(params) },
        "tune": route(TuneParams.self) { state, params in try await state.tune(params) },
        "trackCommands": route(TrackCommandParams.self) { _, params in
            MPVTrackSelector.commands(for: params.selection.trackSelection, trackListJSON: params.trackList)
        },
        "endStream": route(EndStreamParams.self) { state, params in await state.endStream(params) },
    ]

    private struct Request<Params: Decodable>: Decodable {
        let params: Params
    }

    /// A route taking `Params` from the request's `params`.
    private static func route<Params: Decodable & Sendable, Result: Encodable & Sendable>(
        _: Params.Type,
        _ body: @escaping @Sendable (CoreState, Params) async throws -> Result
    ) -> Route {
        { state, data in
            let params = try CoreCoding.decoder.decode(Request<Params>.self, from: data).params
            return AnyEncodable(try await body(state, params))
        }
    }

    /// A route with no parameters.
    private static func route<Result: Encodable & Sendable>(
        _ body: @escaping @Sendable (CoreState) async throws -> Result
    ) -> Route {
        { state, _ in AnyEncodable(try await body(state)) }
    }
}

/// An answer with nothing more to say than that it worked.
struct Done: Encodable, Sendable {
    let done = true
}
