import UIKit
import Kingfisher

/// 셀 표시와 선로딩이 같은 처리 결과를 사용하도록 옵션을 한 곳에서 관리한다.
enum BookCoverImageOptions {
    static let size = CGSize(width: 48, height: 64)

    static func make(displayScale: CGFloat) -> KingfisherOptionsInfo {
        // 픽셀 크기를 processor 식별자에 포함해 서로 다른 배율의 캐시가 섞이지 않게 한다.
        let scale = max(displayScale, 1)
        let pixelSize = CGSize(width: size.width * scale, height: size.height * scale)
        return [
            .processor(DownsamplingImageProcessor(size: pixelSize)),
            .scaleFactor(1)
        ]
    }
}

@MainActor
protocol BookCoverPrefetchTask: AnyObject {
    func start()
    func stop()
}

extension ImagePrefetcher: BookCoverPrefetchTask { }

/// 다음 10개 행의 표지만 준비한다. 창이 이동해도 겹치는 진행 중 요청은 유지한다.
@MainActor
final class BookCoverPrefetcher {
    typealias MakeTask = (URL, CGFloat, @escaping @MainActor () -> Void) -> any BookCoverPrefetchTask

    private struct ActiveRequest {
        let id: UUID
        let task: any BookCoverPrefetchTask
    }

    private let makeTask: MakeTask
    private var desiredURLs: [URL] = []
    private var active: [URL: ActiveRequest] = [:]
    private var finished: Set<URL> = []
    private var displayScale: CGFloat = 1

    init(makeTask: MakeTask? = nil) {
        self.makeTask = makeTask ?? { url, scale, completion in
            let prefetcher = ImagePrefetcher(
                urls: [url],
                options: BookCoverImageOptions.make(displayScale: scale) + [.alsoPrefetchToMemory],
                completionHandler: { _, _, _ in
                    Task { @MainActor in completion() }
                }
            )
            prefetcher.maxConcurrentDownloads = 1
            return prefetcher
        }
    }

    func update(books: [Book], after lastVisibleRow: Int, displayScale: CGFloat) {
        let scale = max(displayScale, 1)
        if self.displayScale != scale { stop() }
        self.displayScale = scale
        guard books.indices.contains(lastVisibleRow) else {
            stop()
            return
        }
        let start = lastVisibleRow + 1
        let end = min(start + 10, books.count)
        var seen = Set<URL>()
        desiredURLs = books[start..<end].compactMap(\.coverURL).filter { seen.insert($0).inserted }
        let desired = Set(desiredURLs)
        finished.formIntersection(desired)
        for url in Array(active.keys) where !desired.contains(url) {
            let request = active.removeValue(forKey: url)
            request?.task.stop()
        }
        startNextRequests()
    }

    func stop() {
        desiredURLs = []
        finished = []
        let requests = Array(active.values)
        active.removeAll()
        requests.forEach { $0.task.stop() }
    }

    private func startNextRequests() {
        while active.count < 2,
              let url = desiredURLs.first(where: { active[$0] == nil && !finished.contains($0) }) {
            let id = UUID()
            let task = makeTask(url, displayScale) { [weak self] in
                guard let self, self.active[url]?.id == id else { return }
                self.active.removeValue(forKey: url)
                // 실패도 현재 창에서는 재시도하지 않는다. 실제 셀 표시 요청은 별도로 진행된다.
                self.finished.insert(url)
                self.startNextRequests()
            }
            active[url] = ActiveRequest(id: id, task: task)
            task.start()
        }
    }
}
