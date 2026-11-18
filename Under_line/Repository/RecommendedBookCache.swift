import Foundation

enum RecommendedBookList: String, Codable, CaseIterable {
    case popular, trending
}

struct RecommendedBookSnapshot: Codable {
    let books: [Book]
    let fetchedAt: Date

    func isFresh(at date: Date) -> Bool {
        let age = date.timeIntervalSince(fetchedAt)
        return age >= 0 && age < 300
    }
}

/// Only two public recommendation lists are persisted; search history is never written here.
@MainActor
final class RecommendedBookCache {
    private let directory: URL?
    private let now: () -> Date
    private var snapshots: [RecommendedBookList: RecommendedBookSnapshot] = [:]

    init(directory: URL? = nil, now: @escaping () -> Date = Date.init) {
        self.directory = directory
        self.now = now
    }

    static func persistent() -> RecommendedBookCache {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("RecommendedBooks-v1", isDirectory: true)
        return RecommendedBookCache(directory: directory)
    }

    func snapshot(for list: RecommendedBookList) -> RecommendedBookSnapshot? {
        #if DEBUG
        let span = BookSearchPerformance.Span(.cacheLookup, source: list == .popular ? .popular : .trending)
        var hit: BookSearchPerformance.Cache = .none
        defer { span.finish(cache: hit) }
        let wasInMemory = snapshots[list] != nil
        #endif
        if snapshots[list] == nil, let url = fileURL(list),
           let data = try? Data(contentsOf: url),
           let snapshot = try? JSONDecoder().decode(RecommendedBookSnapshot.self, from: data) {
            snapshots[list] = snapshot
        }
        guard let snapshot = snapshots[list] else { return nil }
        let age = now().timeIntervalSince(snapshot.fetchedAt)
        guard age >= 0, age < 24 * 60 * 60 else { return nil }
        #if DEBUG
        hit = wasInMemory ? .memory : .disk
        #endif
        return snapshot
    }

    func isFresh(_ snapshot: RecommendedBookSnapshot) -> Bool { snapshot.isFresh(at: now()) }

    func insert(_ books: [Book], for list: RecommendedBookList) -> RecommendedBookSnapshot {
        let snapshot = RecommendedBookSnapshot(books: books, fetchedAt: now())
        snapshots[list] = snapshot
        if let directory, let url = fileURL(list) {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
            } catch {
                // Persistence is best effort; a successful network result remains usable in memory.
            }
        }
        return snapshot
    }

    private func fileURL(_ list: RecommendedBookList) -> URL? {
        directory?.appendingPathComponent(list.rawValue + ".json")
    }
}

/// Each caller owns a waiter. Only the last cancelled waiter cancels the shared request.
@MainActor
final class RecommendedBookLoader {
    private struct Request {
        let id: UUID
        let task: Task<Void, Never>
        var waiters: [UUID: CheckedContinuation<RecommendedBookSnapshot, Error>]
    }

    private let service: Data4LibraryServiceProtocol
    private let cache: RecommendedBookCache
    private var requests: [RecommendedBookList: Request] = [:]

    init(service: Data4LibraryServiceProtocol, cache: RecommendedBookCache) {
        self.service = service
        self.cache = cache
    }

    func snapshot(for list: RecommendedBookList) -> RecommendedBookSnapshot? {
        cache.snapshot(for: list)
    }

    func fetch(_ list: RecommendedBookList, forceRefresh: Bool = false) async throws -> RecommendedBookSnapshot {
        try Task.checkCancellation()
        if !forceRefresh, let snapshot = cache.snapshot(for: list), cache.isFresh(snapshot) {
            return snapshot
        }
        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            let result: RecommendedBookSnapshot = try await withCheckedThrowingContinuation { continuation in
                if var request = requests[list] {
                    request.waiters[waiterID] = continuation
                    requests[list] = request
                    return
                }
                let requestID = UUID()
                let task = Task { [weak self, service] in
                    let result: Result<[Book], Error>
                    do {
                        let books = try await (list == .popular
                            ? service.fetchPopularBooks() : service.fetchTrendingBooks())
                        try Task.checkCancellation()
                        result = .success(books)
                    } catch { result = .failure(error) }
                    self?.finish(list, requestID: requestID, result: result)
                }
                requests[list] = Request(id: requestID, task: task, waiters: [waiterID: continuation])
            }
            try Task.checkCancellation()
            return result
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel(list, waiterID: waiterID) }
        }
    }

    private func cancel(_ list: RecommendedBookList, waiterID: UUID) {
        guard var request = requests[list], let waiter = request.waiters.removeValue(forKey: waiterID) else { return }
        if request.waiters.isEmpty {
            requests.removeValue(forKey: list)
            request.task.cancel()
        } else { requests[list] = request }
        waiter.resume(throwing: CancellationError())
    }

    private func finish(_ list: RecommendedBookList, requestID: UUID, result: Result<[Book], Error>) {
        guard let request = requests[list], request.id == requestID else { return }
        requests.removeValue(forKey: list)
        let snapshot = result.map { cache.insert($0, for: list) }
        request.waiters.values.forEach { $0.resume(with: snapshot) }
    }
}
