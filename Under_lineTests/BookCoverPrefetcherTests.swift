import XCTest
import UIKit
import Kingfisher
@testable import Under_line

@MainActor
final class BookCoverPrefetcherTests: XCTestCase {
    func test_prefetchWindow_limitsRowsAndConcurrentRequests() {
        let fixture = Fixture()
        fixture.prefetcher.update(books: makeBooks(count: 25), after: 3, displayScale: 3)
        XCTAssertEqual(fixture.tasks.map(\.url), [url(4), url(5)])
        var completed = 0
        while completed < fixture.tasks.count {
            XCTAssertLessThanOrEqual(fixture.runningCount, 2)
            fixture.tasks[completed].complete()
            completed += 1
        }
        XCTAssertEqual(fixture.tasks.map(\.url), (4...13).map(url))
        XCTAssertEqual(fixture.runningCount, 0)
    }

    func test_scrolling_preservesOverlappingRequestAndCancelsObsoleteOne() {
        let fixture = Fixture()
        let books = makeBooks(count: 20)
        fixture.prefetcher.update(books: books, after: 0, displayScale: 3)
        let first = fixture.tasks[0]
        let overlapping = fixture.tasks[1]
        fixture.prefetcher.update(books: books, after: 1, displayScale: 3)
        XCTAssertTrue(first.stopped)
        XCTAssertFalse(overlapping.stopped)
        XCTAssertEqual(fixture.tasks.map(\.url), [url(1), url(2), url(3)])
        fixture.prefetcher.update(books: books, after: 1, displayScale: 3)
        XCTAssertEqual(fixture.tasks.count, 3)
    }

    func test_stopAndRestart_ignoresLateCompletionFromPreviousList() {
        let fixture = Fixture()
        let books = makeBooks(count: 20)
        fixture.prefetcher.update(books: books, after: 0, displayScale: 3)
        let oldTasks = fixture.tasks
        fixture.prefetcher.stop()
        XCTAssertTrue(oldTasks.allSatisfy(\.stopped))
        fixture.prefetcher.update(books: books, after: 0, displayScale: 3)
        oldTasks.forEach { $0.complete() }
        XCTAssertEqual(fixture.tasks.count, 4)
        XCTAssertEqual(fixture.runningCount, 2)
        fixture.tasks[2].complete()
        XCTAssertEqual(fixture.tasks.count, 5)
        XCTAssertEqual(fixture.tasks.last?.url, url(3))
    }

    func test_duplicateAndMissingCovers_doNotExpandBeyondTenRows() {
        let fixture = Fixture()
        let books = (0..<15).map { index in
            makeBook(index: index, cover: index < 10 ? nil : url(10))
        }
        fixture.prefetcher.update(books: books, after: 0, displayScale: 3)
        XCTAssertEqual(fixture.tasks.map(\.url), [url(10)])
        fixture.tasks[0].complete()
        fixture.prefetcher.update(books: books, after: 4, displayScale: 3)
        XCTAssertEqual(fixture.tasks.count, 1)
    }

    func test_lastRowOrEmptyList_stopsPrefetching() {
        let fixture = Fixture()
        let books = makeBooks(count: 15)
        fixture.prefetcher.update(books: books, after: 0, displayScale: 3)
        fixture.prefetcher.update(books: books, after: 14, displayScale: 3)
        XCTAssertEqual(fixture.runningCount, 0)
        XCTAssertTrue(fixture.tasks.allSatisfy(\.stopped))
        fixture.prefetcher.update(books: [], after: 0, displayScale: 3)
        XCTAssertEqual(fixture.tasks.count, 2)
    }

    func test_displayScaleChange_restartsWithNewPixelSize() {
        let fixture = Fixture()
        let books = makeBooks(count: 15)
        fixture.prefetcher.update(books: books, after: 0, displayScale: 2)
        let oldTasks = fixture.tasks
        fixture.prefetcher.update(books: books, after: 0, displayScale: 3)
        XCTAssertTrue(oldTasks.allSatisfy(\.stopped))
        XCTAssertEqual(fixture.tasks.map(\.scale), [2, 2, 3, 3])
    }

    func test_downsampling_usesRetinaPixelSizeAndDistinctCacheIdentifier() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let data = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 800), format: format)
            .pngData { context in
                UIColor.red.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 600, height: 800))
            }
        let options2x = KingfisherParsedOptionsInfo(BookCoverImageOptions.make(displayScale: 2))
        let options3x = KingfisherParsedOptionsInfo(BookCoverImageOptions.make(displayScale: 3))
        let image = try XCTUnwrap(options3x.processor.process(item: .data(data), options: options3x))
        XCTAssertEqual(image.cgImage?.width, 144)
        XCTAssertEqual(image.cgImage?.height, 192)
        XCTAssertNotEqual(options2x.processor.identifier, options3x.processor.identifier)
    }

    private func url(_ index: Int) -> URL {
        URL(string: "https://example.invalid/cover/\(index).jpg")!
    }

    private func makeBooks(count: Int) -> [Book] {
        (0..<count).map { makeBook(index: $0, cover: url($0)) }
    }

    private func makeBook(index: Int, cover: URL?) -> Book {
        Book(title: "테스트", author: "저자", isbn13: "\(index)", coverURL: cover,
             publisher: "출판사", publishDate: nil, category: nil, bestRank: nil,
             description: "", itemPage: nil, currentPage: nil)
    }
}

@MainActor
private final class Fixture {
    var tasks: [StubPrefetchTask] = []
    lazy var prefetcher = BookCoverPrefetcher { [unowned self] url, scale, completion in
        let task = StubPrefetchTask(url: url, scale: scale, completion: completion)
        self.tasks.append(task)
        return task
    }
    var runningCount: Int { tasks.filter { $0.started && !$0.stopped && !$0.completed }.count }
}

@MainActor
private final class StubPrefetchTask: BookCoverPrefetchTask {
    let url: URL
    let scale: CGFloat
    let completion: () -> Void
    var started = false
    var stopped = false
    var completed = false

    init(url: URL, scale: CGFloat, completion: @escaping () -> Void) {
        self.url = url
        self.scale = scale
        self.completion = completion
    }

    func start() { started = true }
    func stop() { stopped = true }
    func complete() {
        completed = true
        completion()
    }
}
