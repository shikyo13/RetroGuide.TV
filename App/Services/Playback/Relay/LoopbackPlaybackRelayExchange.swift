import Foundation
import Network
import RetroGuideKit

/// One HTTP request, streamed with bounded buffering and closed after the response.
@MainActor
final class LoopbackPlaybackRelayExchange: NSObject, @preconcurrency URLSessionDataDelegate {
    private let id: UUID
    private let connection: NWConnection
    private weak var relay: LoopbackPlaybackRelay?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var deadline: Task<Void, Never>?
    private var header = Data()
    private var manifest = Data()
    private var mediaPrefix = Data()
    private var inspectedMedia = false
    private var manifestBase: URL?
    private var isHead = false
    private var sentHeaders = false
    private var ended = false
    private var suspended = false
    private var sending = false
    private var upstreamDone = false
    private var queued: [Data] = []
    private var queuedBytes = 0

    init(id: UUID, connection: NWConnection, relay: LoopbackPlaybackRelay) {
        self.id = id
        self.connection = connection
        self.relay = relay
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                if case .failed = state { self?.cancel() }
                if case .cancelled = state { self?.cancel() }
            }
        }
        connection.start(queue: .main)
        resetDeadline()
        receiveHeader()
    }

    func cancel() {
        guard !ended else { return }
        ended = true
        deadline?.cancel()
        task?.cancel()
        session?.invalidateAndCancel()
        session = nil
        task = nil
        connection.cancel()
        queued.removeAll()
        manifest.removeAll()
        relay?.finished(id)
    }

    private func resetDeadline() {
        deadline?.cancel()
        deadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(LoopbackPlaybackRelay.Limits.timeout)) }
            catch { return }
            self?.cancel()
        }
    }

    private func receiveHeader() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: LoopbackPlaybackRelay.Limits.headerBytes) {
            [weak self] data, _, complete, error in
            MainActor.assumeIsolated {
                guard let self, !self.ended else { return }
                if let data { self.header.append(data) }
                guard self.header.count <= LoopbackPlaybackRelay.Limits.headerBytes, error == nil else { self.cancel(); return }
                if self.header.range(of: Data("\r\n\r\n".utf8)) != nil { self.openRequest() }
                else if complete { self.cancel() }
                else { self.receiveHeader() }
            }
        }
    }

    private func openRequest() {
        guard let text = String(data: header, encoding: .utf8) else { reject(400); return }
        let lines = text.components(separatedBy: "\r\n")
        let first = lines[0].split(separator: " ")
        guard first.count == 3, ["GET", "HEAD"].contains(first[0]), first[2] == "HTTP/1.1" else {
            reject(400); return
        }
        var fields: [String: String] = [:]
        for line in lines.dropFirst() {
            if line.isEmpty { break }
            guard let colon = line.firstIndex(of: ":") else { reject(400); return }
            let name = line[..<colon].lowercased()
            guard fields[name] == nil else { reject(400); return }
            fields[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard fields["origin"] == nil, fields["transfer-encoding"] == nil,
              fields["content-length"] == nil || fields["content-length"] == "0",
              let url = relay?.resource(path: String(first[1]), host: fields["host"] ?? "") else {
            reject(403); return
        }
        isHead = first[0] == "HEAD"
        var request = URLRequest(url: url)
        request.httpMethod = isHead ? "HEAD" : "GET"
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if let range = fields["range"], url.pathExtension.lowercased() != "m3u8" {
            guard range.range(of: #"^bytes=(?:[0-9]+-[0-9]*|-[0-9]+)$"#, options: .regularExpression) != nil else {
                reject(400); return
            }
            request.setValue(range, forHTTPHeaderField: "Range")
        }
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = LoopbackPlaybackRelay.Limits.timeout
        let session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        self.session = session
        let task = session.dataTask(with: request)
        self.task = task
        header.removeAll()
        task.resume()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        guard let source = response.url, let destination = request.url,
              SecureTransport.permitsRedirect(from: source, to: destination) else {
            completionHandler(nil); return
        }
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard !ended, dataTask === task, let http = response as? HTTPURLResponse, [200, 206].contains(http.statusCode),
              let url = http.url, SecureTransport.permits(url) else {
            completionHandler(.cancel); reject(502); return
        }
        resetDeadline()
        if !isHead && (url.pathExtension.lowercased() == "m3u8" || http.mimeType?.lowercased().contains("mpegurl") == true) {
            if http.statusCode == 206, var fullRequest = dataTask.originalRequest,
               fullRequest.value(forHTTPHeaderField: "Range") != nil {
                fullRequest.setValue(nil, forHTTPHeaderField: "Range")
                let replacement = session.dataTask(with: fullRequest)
                task = replacement
                completionHandler(.cancel)
                replacement.resume()
                return
            }
            guard response.expectedContentLength <= LoopbackPlaybackRelay.Limits.manifestBytes else {
                completionHandler(.cancel); reject(502); return
            }
            manifestBase = url
        } else {
            var headers = ["Content-Type": http.mimeType ?? "application/octet-stream", "Accept-Ranges": "bytes"]
            if let range = http.value(forHTTPHeaderField: "Content-Range") { headers["Content-Range"] = range }
            if isHead { headers["Content-Length"] = String(max(0, http.expectedContentLength)) }
            else { headers["Transfer-Encoding"] = "chunked" }
            sendHeaders(http.statusCode, headers)
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !ended, dataTask === task else { return }
        resetDeadline()
        if manifestBase != nil {
            guard manifest.count + data.count <= LoopbackPlaybackRelay.Limits.manifestBytes else { reject(502); return }
            manifest.append(data)
        } else if !isHead {
            if !suspended { dataTask.suspend(); suspended = true }
            forwardMedia(data)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard !ended, task === self.task else { return }
        if error != nil { reject(502); return }
        if let base = manifestBase {
            do {
                guard let relay else { cancel(); return }
                let body = try LoopbackPlaybackRelayManifest.rewrite(manifest, base: base, register: relay.register)
                manifest.removeAll()
                guard body.count <= LoopbackPlaybackRelay.Limits.manifestBytes else { reject(502); return }
                sendHeaders(200, ["Content-Type": "application/vnd.apple.mpegurl", "Transfer-Encoding": "chunked"])
                enqueue(chunk(body))
            } catch { reject(502); return }
        }
        if manifestBase == nil && !isHead { forwardMedia(Data(), complete: true) }
        guard !ended else { return }
        upstreamDone = true
        if !isHead { enqueue(Data("0\r\n\r\n".utf8)) }
        drain()
    }

    private func forwardMedia(_ data: Data, complete: Bool = false) {
        guard !inspectedMedia else { if !data.isEmpty { enqueue(chunk(data)) }; return }
        guard mediaPrefix.count + data.count <= LoopbackPlaybackRelay.Limits.bufferedBytes else { cancel(); return }
        mediaPrefix.append(data)
        if !complete && mediaPrefix.count < LoopbackPlaybackRelay.Limits.sniffBytes {
            if suspended { suspended = false; task?.resume() }
            return
        }
        var prefix = mediaPrefix[...]
        if prefix.starts(with: [0xEF, 0xBB, 0xBF]) { prefix = prefix.dropFirst(3) }
        prefix = prefix.drop(while: { [9, 10, 13, 32].contains($0) })
        let signature = Data("#EXTM3U".utf8)
        if prefix.starts(with: signature) || (complete && !prefix.isEmpty && signature.starts(with: prefix)) {
            // A mislabeled playlist must never reach Apple's independent URL loader.
            reject(502)
            return
        }
        if !complete && (prefix.isEmpty || signature.starts(with: prefix)) {
            guard mediaPrefix.count < LoopbackPlaybackRelay.Limits.headerBytes else { reject(502); return }
            // Resume a suspended task until enough prefix bytes arrive to classify it.
            if suspended { suspended = false; task?.resume() }
            return
        }
        inspectedMedia = true
        let body = mediaPrefix
        mediaPrefix.removeAll()
        if !body.isEmpty { enqueue(chunk(body)) }
    }

    private func chunk(_ data: Data) -> Data {
        var result = Data("\(String(data.count, radix: 16))\r\n".utf8)
        result.append(data)
        result.append(Data("\r\n".utf8))
        return result
    }

    private func sendHeaders(_ status: Int, _ fields: [String: String]) {
        guard !sentHeaders else { return }
        sentHeaders = true
        var text = "HTTP/1.1 \(status) Response\r\nConnection: close\r\nCache-Control: no-store\r\n"
        for (key, value) in fields {
            guard !value.contains("\r"), !value.contains("\n") else { cancel(); return }
            text += "\(key): \(value)\r\n"
        }
        enqueue(Data((text + "\r\n").utf8))
    }

    private func enqueue(_ data: Data) {
        guard !ended, queuedBytes + data.count <= LoopbackPlaybackRelay.Limits.bufferedBytes else { cancel(); return }
        queued.append(data)
        queuedBytes += data.count
        drain()
    }

    private func drain() {
        guard !ended, !sending else { return }
        guard !queued.isEmpty else {
            if upstreamDone { cancel() }
            else if suspended { suspended = false; task?.resume() }
            return
        }
        sending = true
        let data = queued.removeFirst()
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            MainActor.assumeIsolated {
                guard let self, !self.ended else { return }
                self.queuedBytes -= data.count
                self.sending = false
                if error != nil { self.cancel(); return }
                self.drain()
            }
        })
    }

    private func reject(_ status: Int) {
        guard !ended else { return }
        task?.cancel()
        if sentHeaders { cancel(); return }
        sendHeaders(status, ["Content-Length": "0"])
        upstreamDone = true
        drain()
    }
}
