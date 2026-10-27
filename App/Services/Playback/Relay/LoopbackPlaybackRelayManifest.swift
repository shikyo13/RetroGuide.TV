import Foundation
import RetroGuideKit

@MainActor
enum LoopbackPlaybackRelayManifest {
    /// Rewrites playlists, keys, maps, alternate tracks and segment URIs through the relay.
    static func rewrite(_ data: Data, base: URL, register: (URL) throws -> URL) throws -> Data {
        guard let text = String(data: data, encoding: .utf8), text.hasPrefix("#EXTM3U") else {
            throw HTTPError.invalidResponse
        }
        let references = try NSRegularExpression(pattern: #"(?:[A-Z-]*URI|URL)\s*="#)
        let attributes = try NSRegularExpression(pattern: #"(?:[A-Z-]*URI|URL)="([^\"]*)""#)
        func local(_ value: String) throws -> String {
            guard !value.contains("{$"), let url = URL(string: value, relativeTo: base)?.absoluteURL,
                  SecureTransport.permits(url) else { throw HTTPError.secureConnectionRequired }
            return try register(url).absoluteString
        }
        func rewriteLine(_ raw: String) throws -> String {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { return line }
            if !line.hasPrefix("#") { return try local(line) }
            // Dynamic steering and variable expansion can introduce unregistered destinations.
            guard !line.hasPrefix("#EXT-X-CONTENT-STEERING"), !line.hasPrefix("#EXT-X-DEFINE") else {
                throw HTTPError.invalidResponse
            }
            let wholeLine = NSRange(line.startIndex..., in: line)
            guard references.numberOfMatches(in: line, range: wholeLine) == attributes.numberOfMatches(in: line, range: wholeLine) else {
                throw HTTPError.invalidResponse
            }
            var result = line
            for match in attributes.matches(in: line, range: NSRange(line.startIndex..., in: line)).reversed() {
                guard let range = Range(match.range(at: 1), in: result) else { throw HTTPError.invalidResponse }
                result.replaceSubrange(range, with: try local(String(result[range])))
            }
            return result
        }
        var output = Data()
        for line in text.components(separatedBy: .newlines) {
            let rewritten = Data((try rewriteLine(line) + "\n").utf8)
            guard output.count + rewritten.count <= LoopbackPlaybackRelay.Limits.manifestBytes else {
                throw HTTPError.invalidResponse
            }
            output.append(rewritten)
        }
        return output
    }
}
