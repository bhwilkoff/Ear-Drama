#if os(iOS) || os(macOS)
import Foundation

/// The production transport: a background URLSession, so `nsurlsessiond`
/// carries the transfer while the app is suspended and finishes it even after
/// the app is terminated, relaunching it in the background to be told (iOS).
///
/// The delegate queue is `.main`, so every callback lands on the main thread
/// and `MainActor.assumeIsolated` is sound. A task's identity survives a
/// relaunch only through `taskDescription`, which carries the record's token.
final class BackgroundDownloadTransport: DownloadTransport {
    weak var store: DownloadStore?

    private let shim = SessionShim()
    private var tasks: [String: URLSessionDownloadTask] = [:]
    private var backgroundEvents: CheckedContinuation<Void, Never>?

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: DownloadStore.sessionIdentifier)
        // The listener asked for this episode and is watching it come in: not
        // discretionary work for the system to defer.
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        // A whole run is hundreds of tasks; archive.org gets four at a time
        // (Decision 071). Its 302 to a storage node is followed by default.
        config.httpMaximumConnectionsPerHost = 4
        shim.transport = self
        return URLSession(configuration: config, delegate: shim, delegateQueue: .main)
    }()

    func begin(token: String, url: URL) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        let task = session.downloadTask(with: request)
        task.taskDescription = token
        tasks[token] = task
        task.resume()
    }

    func cancel(token: String) {
        tasks.removeValue(forKey: token)?.cancel()
        // A task restored by a relaunch may not be indexed yet.
        let session = self.session
        Task {
            for task in await session.allTasks where task.taskDescription == token { task.cancel() }
        }
    }

    func cancelAll() {
        tasks.removeAll()
        session.getAllTasks { tasks in tasks.forEach { $0.cancel() } }
    }

    func liveTokens() async -> Set<String> {
        var live: Set<String> = []
        for task in await session.allTasks {
            guard let token = task.taskDescription, task.state != .completed, task.state != .canceling else { continue }
            live.insert(token)
            if let download = task as? URLSessionDownloadTask { tasks[token] = download }
        }
        return live
    }

    func finishBackgroundEvents() async {
        _ = session
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            guard backgroundEvents == nil else { continuation.resume(); return }
            backgroundEvents = continuation
            // A session that never reports finished would hold the app in the
            // background until the watchdog kills it.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(25))
                self?.eventsDelivered()
            }
        }
    }

    fileprivate func eventsDelivered() {
        backgroundEvents?.resume()
        backgroundEvents = nil
    }

    fileprivate func forget(_ token: String) { tasks[token] = nil }
}

/// The session's delegate, kept apart so the transport can stay on the main
/// actor while these callbacks satisfy a nonisolated protocol.
nonisolated private final class SessionShim: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    weak var transport: BackgroundDownloadTransport?

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let token = downloadTask.taskDescription else { return }
        MainActor.assumeIsolated {
            transport?.store?.transferProgressed(token: token, received: totalBytesWritten,
                                                 expected: totalBytesExpectedToWrite)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let token = downloadTask.taskDescription else { return }
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode
        MainActor.assumeIsolated {
            transport?.forget(token)
            transport?.store?.transferFinished(token: token, location: location, httpStatus: status)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let token = task.taskDescription, let error else { return }
        let ns = error as NSError
        let cancelled = ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
        let message = error.localizedDescription
        MainActor.assumeIsolated {
            transport?.forget(token)
            guard !cancelled else { return }
            transport?.store?.transferFailed(token: token, message: message)
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        MainActor.assumeIsolated { transport?.eventsDelivered() }
    }
}
#endif
