import Foundation

/// A track's name in the style Plex uses, "English (AC3 5.1)" or
/// "Commentary (English AAC Stereo)", so tracks read the same whichever
/// server a program comes from. Jellyfin's own `DisplayTitle` reads
/// "English - Default - SUBRIP".
enum JellyfinTrackTitle {
    private static let codecNames = [
        "aac": "AAC", "ac3": "AC3", "eac3": "EAC3", "truehd": "TrueHD", "dts": "DTS", "flac": "FLAC", "opus": "Opus",
        "mp3": "MP3", "vorbis": "Vorbis", "pcm_s16le": "PCM", "pcm_s24le": "PCM",
        "subrip": "SRT", "srt": "SRT", "ass": "ASS", "ssa": "SSA", "webvtt": "VTT", "vtt": "VTT", "mov_text": "MOV_TEXT",
        "pgssub": "PGS", "hdmv_pgs_subtitle": "PGS", "dvdsub": "VobSub", "dvd_subtitle": "VobSub", "dvbsub": "DVB",
    ]
    private static let channelNames = [1: "Mono", 2: "Stereo", 6: "5.1", 8: "7.1"]
    private static let forced = "Forced"
    private static let hearingImpaired = "SDH"

    static func title(for stream: JellyfinMediaStream) -> String {
        let language = LanguageCode.normalized(stream.language)
            .flatMap { Locale.current.localizedString(forLanguageCode: $0) } ?? stream.language
        var name = [language, stream.isForced == true ? forced : nil].compactMap { $0 }.joined(separator: " ")
        let format = [codec(stream.codec), stream.channels.map { channelNames[$0] ?? "\($0)ch" }].compactMap { $0 }.joined(separator: " ")
        let label = stream.title.flatMap { $0.isEmpty ? nil : $0 }
            ?? (stream.isHearingImpaired == true ? hearingImpaired : nil)
        if let label, label.caseInsensitiveCompare(name) != .orderedSame {
            return "\(label) (\([name, format].filter { !$0.isEmpty }.joined(separator: " ")))"
        }
        if name.isEmpty { name = JellyfinAPI.Defaults.unknownTrackTitle }
        return format.isEmpty ? name : "\(name) (\(format))"
    }

    private static func codec(_ codec: String?) -> String? {
        guard let codec = codec?.lowercased(), !codec.isEmpty else { return nil }
        return codecNames[codec] ?? codec.uppercased()
    }
}
