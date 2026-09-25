import Foundation
import RetroGuideKit

/// Translates a server's ``TrackSelection`` into mpv commands.
///
/// Servers identify tracks by container stream index; mpv numbers tracks per
/// type. mpv's `track-list` exposes each track's `ff-index` (the container
/// index), which links the two.
enum MPVTrackSelector {
    private enum TrackListKey {
        static let id = "id"
        static let type = "type"
        static let containerIndex = "ff-index"
    }

    private enum TrackType {
        static let audio = "audio"
        static let subtitle = "sub"
    }

    private enum Property {
        static let audio = "aid"
        static let subtitle = "sid"
        static let off = "no"
    }

    /// Commands that apply `selection` to the loaded file described by `trackListJSON`.
    static func commands(for selection: TrackSelection, trackListJSON: String) -> [[String]] {
        let tracks = parse(trackListJSON)
        var commands: [[String]] = []
        if let index = selection.audioStreamIndex, let id = trackID(of: TrackType.audio, containerIndex: index, in: tracks) {
            commands.append(["set", Property.audio, String(id)])
        }
        switch selection.subtitle {
        case .none:
            commands.append(["set", Property.subtitle, Property.off])
        case let .embedded(index):
            if let id = trackID(of: TrackType.subtitle, containerIndex: index, in: tracks) {
                commands.append(["set", Property.subtitle, String(id)])
            }
        case let .external(url):
            commands.append(["sub-add", url.absoluteString, "select"])
        }
        return commands
    }

    private static func parse(_ json: String) -> [[String: Any]] {
        guard let data = json.data(using: .utf8),
              let tracks = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return tracks
    }

    private static func trackID(of type: String, containerIndex: Int, in tracks: [[String: Any]]) -> Int? {
        tracks.first {
            ($0[TrackListKey.type] as? String) == type && ($0[TrackListKey.containerIndex] as? Int) == containerIndex
        }?[TrackListKey.id] as? Int
    }
}
