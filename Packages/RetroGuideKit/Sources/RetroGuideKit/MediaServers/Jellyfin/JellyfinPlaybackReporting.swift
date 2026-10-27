import Foundation

extension JellyfinServerClient {
    public var reportsPlayback: Bool { true }

    /// Jellyfin remembers audio and subtitle choices from playback progress,
    /// according to the user's RememberAudio/SubtitleSelections settings.
    public func reportPlayback(_ report: PlaybackReport) async -> Bool {
        guard let version = report.item.versions.first(where: { $0.index == report.request.versionIndex }),
              let sourceID = version.filePath else { return false }
        // An unknown selection must not erase a remembered server preference.
        if report.event == .progress, report.selection == nil || report.tracks == nil { return false }
        let path: String
        switch report.event {
        case .started: path = JellyfinAPI.Path.playbackStart
        case .progress: path = JellyfinAPI.Path.playbackProgress
        case .stopped: path = JellyfinAPI.Path.playbackStopped
        }
        do {
            var request = try context.builder(timeout: JellyfinAPI.Defaults.playbackReportTimeout).request(
                path: path, method: "POST", extraHeaders: [JellyfinAPI.Header.contentType: JellyfinAPI.Header.json]
            )
            request.httpBody = try JellyfinCoding.encoder.encode(JellyfinPlaybackState(report, sourceID: sourceID))
            _ = try await context.playbackHTTP.data(for: request)
            return true
        } catch { return false }
    }
}

private struct JellyfinPlaybackState: Encodable {
    let itemId: String
    let mediaSourceId: String
    let playSessionId: String
    let positionTicks: Int64
    let isPaused: Bool
    let canSeek = true
    let playMethod: String
    let audioStreamIndex: Int?
    let subtitleStreamIndex: Int?

    init(_ report: PlaybackReport, sourceID: String) {
        itemId = report.item.itemKey
        mediaSourceId = sourceID
        playSessionId = report.request.sessionID
        // Bound before converting so malformed durations cannot overflow Int64.
        let seconds = min(report.position, Double(Int64.max / Int64(JellyfinAPI.Defaults.ticksPerSecond)))
        positionTicks = Int64(seconds * JellyfinAPI.Defaults.ticksPerSecond)
        isPaused = report.isPaused
        playMethod = report.request.method == .directPlay ? "DirectPlay" : "DirectStream"
        if let selection = report.selection, let tracks = report.tracks {
            audioStreamIndex = tracks.audioOption(for: selection)?.serverStreamIndex
            subtitleStreamIndex = selection.subtitle == .none ? -1 : tracks.subtitleOption(for: selection)?.serverStreamIndex
        } else {
            audioStreamIndex = nil
            subtitleStreamIndex = nil
        }
    }
}
