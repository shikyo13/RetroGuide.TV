#if DEBUG
import AudioToolbox
import AVFoundation

/// Development only: records what the audio route reports when set up the way
/// libmpv's AudioUnit output does (movie playback, preferred channel count,
/// RemoteIO channel layout), to diagnose multichannel output problems on
/// devices. Written to `Library/Caches/audio-probe.txt` (tvOS apps can't write Documents).
enum AudioRouteProbe {
    private static let fileName = "audio-probe.txt"
    private static let requestedChannels = 6
    /// Long enough after launch for the first channel to be playing.
    static let playbackCheckDelay = Duration.seconds(20)

    static func run() {
        var lines: [String] = []
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)
        lines.append("max output channels: \(session.maximumOutputNumberOfChannels)")
        lines.append("output channels before: \(session.outputNumberOfChannels)")
        let preferred = min(session.maximumOutputNumberOfChannels, requestedChannels)
        do {
            try session.setPreferredOutputNumberOfChannels(preferred)
        } catch {
            lines.append("setPreferredOutputNumberOfChannels(\(preferred)) failed: \(error)")
        }
        lines.append("output channels after preferring \(preferred): \(session.outputNumberOfChannels)")
        for output in session.currentRoute.outputs {
            let channels = output.channels?.map { "\($0.channelName)#\($0.channelLabel)" } ?? []
            lines.append("route output: \(output.portType.rawValue) \"\(output.portName)\" channels: \(channels)")
        }
        lines.append(contentsOf: remoteIOLayout())
        write(lines.joined(separator: "\n"))
    }

    /// The channel layout RemoteIO reports on its output, which libmpv copies.
    private static func remoteIOLayout() -> [String] {
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_RemoteIO,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &description) else { return ["no RemoteIO"] }
        var unit: AudioUnit?
        guard AudioComponentInstanceNew(component, &unit) == noErr, let unit else { return ["RemoteIO create failed"] }
        defer { AudioComponentInstanceDispose(unit) }
        AudioUnitInitialize(unit)
        defer { AudioUnitUninitialize(unit) }
        var size: UInt32 = 0
        var status = AudioUnitGetPropertyInfo(unit, kAudioUnitProperty_AudioChannelLayout, kAudioUnitScope_Output, 0, &size, nil)
        guard status == noErr, size > 0 else { return ["layout size status \(status)"] }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioChannelLayout>.alignment)
        defer { raw.deallocate() }
        status = AudioUnitGetProperty(unit, kAudioUnitProperty_AudioChannelLayout, kAudioUnitScope_Output, 0, raw, &size)
        guard status == noErr else { return ["layout status \(status)"] }
        let layout = raw.assumingMemoryBound(to: AudioChannelLayout.self)
        let tag = layout.pointee.mChannelLayoutTag
        let count = layout.pointee.mNumberChannelDescriptions
        var labels: [String] = []
        withUnsafeMutablePointer(to: &layout.pointee.mChannelDescriptions) { first in
            let descriptions = UnsafeBufferPointer(start: first, count: Int(count))
            labels = descriptions.map { "\($0.mChannelLabel)" }
        }
        return [
            "RemoteIO layout tag: 0x\(String(tag, radix: 16)) (\(AudioChannelLayoutTag_GetNumberOfChannels(tag)) channels by tag)",
            "RemoteIO layout bitmap: 0x\(String(layout.pointee.mChannelBitmap.rawValue, radix: 16))",
            "RemoteIO layout descriptions: \(count) labels \(labels)",
        ]
    }

    /// Appends the session's current route-sharing policy and output, to check
    /// what the player's own session setup left in place during playback.
    static func recordPlaybackState() {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs.map { "\($0.portType.rawValue) \"\($0.portName)\"" }
        let line = "during playback: policy \(session.routeSharingPolicy.rawValue), mode \(session.mode.rawValue), outputs \(outputs), outputLatency \(session.outputLatency)s, ioBuffer \(session.ioBufferDuration)s"
        guard let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let url = folder.appending(path: fileName)
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try? (existing + "\n" + line).write(to: url, atomically: true, encoding: .utf8)
    }

    private static func write(_ text: String) {
        guard let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        try? text.write(to: folder.appending(path: fileName), atomically: true, encoding: .utf8)
    }
}
#endif
