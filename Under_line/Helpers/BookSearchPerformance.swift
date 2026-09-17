#if DEBUG
import Foundation
import OSLog

/// DEBUG 전용 구간 측정. 검색어, URL, 응답, 오류 설명은 기록하지 않는다.
@MainActor
enum BookSearchPerformance {
    enum Stage: String {
        case responseDecoded
        case domainMapping
        case firstCellWillDisplay
        case coverLoaded
    }

    enum Source: String {
        case bestseller, newSpecial, search, table
    }

    enum Outcome: String {
        case success, failed, cancelled, superseded, notDisplayed, noURL
    }

    enum Cache: String {
        case none, memory, disk, notApplicable
    }

    /// request/매핑은 같은 id, 테이블/표지는 같은 id로 묶는다.
    /// id는 계측용 임의 값이며 도서나 검색어 식별자가 아니다.
    final class Span {
        let id: UUID
        private let stage: Stage
        private let source: Source
        private let startedAt = ProcessInfo.processInfo.systemUptime
        private var isFinished = false

        init(_ stage: Stage, source: Source, id: UUID = UUID()) {
            self.id = id
            self.stage = stage
            self.source = source
        }

        func finish(_ outcome: Outcome = .success, count: Int = 0, cache: Cache = .notApplicable) {
            guard !isFinished else { return }
            let milliseconds = (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
            isFinished = true
            logger.notice("id=\(self.id.uuidString, privacy: .public) stage=\(self.stage.rawValue, privacy: .public) source=\(self.source.rawValue, privacy: .public) ms=\(milliseconds, format: .fixed(precision: 3)) outcome=\(outcome.rawValue, privacy: .public) count=\(count) cache=\(cache.rawValue, privacy: .public)")
        }
    }

    private static let logger = Logger(subsystem: "com.jade.UnderLine", category: "BookSearchPerformance")
}
#endif
