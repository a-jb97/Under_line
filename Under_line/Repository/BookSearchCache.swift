import Foundation

/// Repository 수명 동안만 유지하는 원격 목록 캐시. SwiftData에는 저장하지 않는다.
@MainActor
final class BookSearchCache {
    enum Key: Hashable {
        case bestseller
        case newSpecial(page: Int)
        case search(query: String, page: Int)
    }

    typealias Result = (books: [Book], totalResults: Int)

    private struct Entry {
        let result: Result
        let expiresAt: TimeInterval
    }

    private let now: () -> TimeInterval
    private let lifetime: TimeInterval = 5 * 60
    private let capacity = 30
    private var entries: [Key: Entry] = [:]
    // 앞쪽이 가장 오래 사용하지 않은 키. 최대 30개이므로 선형 갱신한다.
    private var accessOrder: [Key] = []

    init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.now = now
    }

    func result(for key: Key) -> Result? {
        guard let entry = entries[key] else { return nil }
        guard now() < entry.expiresAt else {
            entries.removeValue(forKey: key)
            accessOrder.removeAll { $0 == key }
            return nil
        }
        touch(key)
        return entry.result
    }

    func insert(_ result: Result, for key: Key) {
        let timestamp = now()
        // 만료된 항목 때문에 유효한 항목이 밀려나지 않게 먼저 정리한다.
        entries = entries.filter { timestamp < $0.value.expiresAt }
        accessOrder.removeAll { entries[$0] == nil }
        entries[key] = Entry(result: result, expiresAt: timestamp + lifetime)
        touch(key)
        if accessOrder.count > capacity {
            entries.removeValue(forKey: accessOrder.removeFirst())
        }
    }

    private func touch(_ key: Key) {
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
    }
}
