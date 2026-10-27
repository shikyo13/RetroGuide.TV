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
        "playback.event": route(PlaybackEventParams.self) { state, params in await state.playbackEvent(params) },

        "options": route(ChannelParams.self) { state, params in try await state.options(channelID: params.channelID) },
        "tracks.choose": route(TrackChoiceParams.self) { state, params in try await state.chooseTrack(params) },
        "subtitles.nudge": route(SubtitleNudgeParams.self) { state, params in await state.nudgeSubtitles(params) },

        "channel.setOrdering": route(OrderingParams.self) { state, params in try await state.setOrdering(params) },
        "channel.removeTitle": route(TitleParams.self) { state, params in await state.removeTitle(params) },
        "channel.restoreTitle": route(TitleParams.self) { state, params in await state.restoreTitle(params) },
        "channel.setHidden": route(HiddenParams.self) { state, params in await state.setHidden(params) },
        "favorites.toggle": route(ChannelParams.self) { state, params in try await state.toggleFavorite(params) },
        "viewing": route { state in await state.viewingInfo() },
        "viewing.favoritesOnly": route(EnabledParams.self) { state, params in await state.setFavoritesOnly(params) },
        "pro.set": route(EnabledParams.self) { state, params in await state.setPro(params) },
        "search": route(SearchParams.self) { state, params in await state.search(params) },
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
