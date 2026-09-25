import Foundation
import Libmpv
import OSLog
import QuartzCore

/// Owns one libmpv instance: configuration, commands and the event loop.
///
/// libmpv is thread-safe; events are drained on a private serial queue and
/// forwarded with the generation of the load they belong to.
final class MPVCore: @unchecked Sendable {
    typealias EventHandler = @Sendable (PlaybackEvent, Int) -> Void

    /// mpv options (https://mpv.io/manual/stable/#options).
    private enum Option {
        static let values: [(String, String)] = [
            // Cheap scalers and no debanding: TV-box friendly, avoids dropped frames at 4K.
            ("profile", "fast"),
            // Rendering: Vulkan via MoltenVK onto our CAMetalLayer, hardware decoding.
            ("vo", "gpu-next"),
            ("gpu-api", "vulkan"),
            ("gpu-context", "moltenvk"),
            ("hwdec", "videotoolbox"),
            ("video-rotate", "no"),
            // Per-frame HDR peak analysis is expensive; static metadata is good enough on TV.
            ("hdr-compute-peak", "no"),
            // Bounded network cache keeps memory predictable on Apple TV.
            ("cache", "yes"),
            ("demuxer-max-bytes", "64MiB"),
            ("demuxer-max-back-bytes", "16MiB"),
            ("network-timeout", "20"),
            // Subtitles like broadcast TV / Plex "shown with foreign audio": subtitles in
            // the viewer's language appear when the audio is in another language; when the
            // audio already matches, only forced subtitles (signs, foreign dialogue) show.
            // A file's default track in some other language is never picked.
            ("subs-match-os-language", "yes"),
            ("subs-fallback", "no"),
            ("subs-fallback-forced", "yes"),
            ("subs-with-matching-audio", "forced"),
            // Behave like an embedded engine, not a desktop player.
            ("idle", "yes"),
            ("keep-open", "no"),
            ("input-default-bindings", "no"),
            ("ytdl", "no"),
            ("terminal", "no"),
            ("audio-client-name", "RetroGuide.TV"),
        ]
        static let startPositionProperty = "start"
        static let noStartPosition = "none"
        static let windowID = "wid"
        /// libmpv log verbosity forwarded to the unified log in debug builds.
        static let debugLogLevel = "info"
    }

    private static let logger = Logger(subsystem: "com.adamhunt.retroguide", category: "mpv")

    var onEvent: EventHandler?

    private var handle: OpaquePointer?
    private let queue = DispatchQueue(label: "com.adamhunt.retroguide.mpv", qos: .userInitiated)
    private var currentGeneration = 0
    private let generationLock = NSLock()

    init?(layer: CAMetalLayer) {
        guard let handle = mpv_create() else { return nil }
        self.handle = handle
        var windowID = Int64(Int(bitPattern: Unmanaged.passUnretained(layer).toOpaque()))
        mpv_set_option(handle, Option.windowID, MPV_FORMAT_INT64, &windowID)
        for (name, value) in Option.values {
            mpv_set_option_string(handle, name, value)
        }
        #if DEBUG
        mpv_request_log_messages(handle, Option.debugLogLevel)
        for property in Diagnostics.observedProperties {
            mpv_observe_property(handle, .zero, property, MPV_FORMAT_INT64)
        }
        #endif
        guard mpv_initialize(handle) >= .zero else {
            mpv_terminate_destroy(handle)
            self.handle = nil
            return nil
        }
        mpv_set_wakeup_callback(handle, { context in
            guard let context else { return }
            Unmanaged<MPVCore>.fromOpaque(context).takeUnretainedValue().drainEvents()
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    deinit {
        guard let handle else { return }
        mpv_set_wakeup_callback(handle, nil, nil)
        mpv_terminate_destroy(handle)
    }

    // MARK: - Commands

    /// Loads `url`, optionally starting at `startPosition` seconds.
    func load(_ url: URL, startPosition: TimeInterval?, generation: Int) {
        guard let handle else { return }
        setGeneration(generation)
        let start = startPosition.map { String(format: "%.1f", $0) } ?? Option.noStartPosition
        mpv_set_property_string(handle, Option.startPositionProperty, start)
        command(["loadfile", url.absoluteString, "replace"])
    }

    func stop() {
        command(["stop"])
    }

    private func command(_ arguments: [String]) {
        guard let handle else { return }
        var cStrings = arguments.map { strdup($0) }
        defer { cStrings.forEach { free($0) } }
        var pointers = cStrings.map { UnsafePointer<CChar>($0) } + [nil]
        mpv_command_async(handle, .zero, &pointers)
    }

    // MARK: - Events

    private func setGeneration(_ generation: Int) {
        generationLock.lock()
        currentGeneration = generation
        generationLock.unlock()
    }

    private var generation: Int {
        generationLock.lock()
        defer { generationLock.unlock() }
        return currentGeneration
    }

    private func drainEvents() {
        queue.async { [weak self] in
            guard let self, let handle = self.handle else { return }
            while let event = mpv_wait_event(handle, .zero), event.pointee.event_id != MPV_EVENT_NONE {
                Self.log(event.pointee)
                if let mapped = Self.map(event.pointee) {
                    onEvent?(mapped, generation)
                }
            }
        }
    }

    /// Playback health counters logged in debug builds.
    private enum Diagnostics {
        static let observedProperties = ["frame-drop-count", "decoder-frame-drop-count", "vo-delayed-frame-count"]
    }

    private static func log(_ event: mpv_event) {
        #if DEBUG
        if event.event_id == MPV_EVENT_PROPERTY_CHANGE,
           let property = event.data?.assumingMemoryBound(to: mpv_event_property.self).pointee,
           property.format == MPV_FORMAT_INT64,
           let value = property.data?.assumingMemoryBound(to: Int64.self).pointee {
            logger.notice("stat \(String(cString: property.name), privacy: .public)=\(value)")
        } else if event.event_id == MPV_EVENT_LOG_MESSAGE,
           let message = event.data?.assumingMemoryBound(to: mpv_event_log_message.self).pointee,
           let prefix = message.prefix, let text = message.text {
            logger.notice("[\(String(cString: prefix), privacy: .public)] \(String(cString: text), privacy: .public)")
        } else if let name = mpv_event_name(event.event_id) {
            logger.notice("event \(String(cString: name), privacy: .public)")
        }
        #endif
    }

    private static func map(_ event: mpv_event) -> PlaybackEvent? {
        switch event.event_id {
        case MPV_EVENT_PLAYBACK_RESTART:
            return .playing
        case MPV_EVENT_END_FILE:
            guard let data = event.data?.assumingMemoryBound(to: mpv_event_end_file.self).pointee else { return nil }
            switch data.reason {
            case MPV_END_FILE_REASON_EOF:
                return .ended
            case MPV_END_FILE_REASON_ERROR:
                let message = mpv_error_string(data.error).map { String(cString: $0) } ?? "Playback error"
                return .failed("The video couldn't be played (\(message)).")
            default:
                return nil
            }
        default:
            return nil
        }
    }
}
