//
//  StatisticsViewModel.swift
//  Under_line
//
//  통계 화면 ViewModel — 독서 세션 조회 + 장르/저자별 문장 통계
//

import Foundation
import RxSwift
import RxCocoa

// MARK: - SentenceDonutData

struct SentenceDonutItem {
    let label: String
    let count: Int
}

struct SentenceDonutData {
    let total: Int
    let items: [SentenceDonutItem]
    static let empty = SentenceDonutData(total: 0, items: [])
}

// MARK: - StatisticsViewModel

final class StatisticsViewModel {

    // MARK: - Input

    struct Input {
        let viewWillAppear: Observable<Void>
    }

    // MARK: - Output

    struct Output {
        let allSessions: Driver<[ReadingSession]>
        let genreData: Driver<SentenceDonutData>
        let authorData: Driver<SentenceDonutData>
    }

    // MARK: - Dependencies

    private let readingSessionRepository: ReadingSessionRepositoryProtocol
    private let bookRepository: BookRepositoryProtocol
    private let sentenceRepository: SentenceRepositoryProtocol

    init(
        readingSessionRepository: ReadingSessionRepositoryProtocol,
        bookRepository: BookRepositoryProtocol,
        sentenceRepository: SentenceRepositoryProtocol
    ) {
        self.readingSessionRepository = readingSessionRepository
        self.bookRepository           = bookRepository
        self.sentenceRepository       = sentenceRepository
    }

    // MARK: - Transform

    func transform(input: Input) -> Output {
        let allSessions = input.viewWillAppear
            .flatMapLatest { [weak self] _ -> Observable<[ReadingSession]> in
                guard let self else { return .just([]) }
                return self.readingSessionRepository.fetchAllSessions()
                    .catch { _ in .just([]) }
                    .asObservable()
            }

        let donutData = input.viewWillAppear
            .flatMapLatest { [weak self] _ -> Observable<(SentenceDonutData, SentenceDonutData)> in
                guard let self else { return .just((.empty, .empty)) }
                let books     = self.bookRepository.fetchSavedBooks().take(1)
                let sentences = self.sentenceRepository.fetchAllSentences().asObservable()
                return Observable.zip(books, sentences)
                    .map { books, sentences in
                        let genreData  = Self.computeGenreData(sentences: sentences, books: books)
                        let authorData = Self.computeAuthorData(sentences: sentences, books: books)
                        return (genreData, authorData)
                    }
                    .catch { _ in .just((.empty, .empty)) }
            }

        return Output(
            allSessions: allSessions.asDriver(onErrorJustReturn: []),
            genreData:   donutData.map { $0.0 }.asDriver(onErrorJustReturn: .empty),
            authorData:  donutData.map { $0.1 }.asDriver(onErrorJustReturn: .empty)
        )
    }

    // MARK: - Private helpers

    private static func computeGenreData(sentences: [Sentence], books: [Book]) -> SentenceDonutData {
        var bookMap: [String: Book] = [:]
        for book in books { bookMap[book.isbn13] = book }

        var counts: [String: Int] = [:]
        for sentence in sentences {
            let raw = bookMap[sentence.bookISBN]?.category?.trimmingCharacters(in: .whitespaces) ?? ""
            let key = raw.isEmpty ? "기타" : raw
            counts[key, default: 0] += 1
        }
        return buildDonutData(from: counts, total: sentences.count)
    }

    private static func computeAuthorData(sentences: [Sentence], books: [Book]) -> SentenceDonutData {
        var bookMap: [String: Book] = [:]
        for book in books { bookMap[book.isbn13] = book }

        var counts: [String: Int] = [:]
        for sentence in sentences {
            let fullAuthor  = bookMap[sentence.bookISBN]?.author ?? ""
            let rawFirst = fullAuthor.components(separatedBy: ",").first?
                .trimmingCharacters(in: .whitespaces) ?? ""
            let firstAuthor = rawFirst
                .replacingOccurrences(of: "\\(지은이\\)", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            let key = firstAuthor.isEmpty ? "알 수 없음" : firstAuthor
            counts[key, default: 0] += 1
        }
        return buildDonutData(from: counts, total: sentences.count)
    }

    private static func buildDonutData(from counts: [String: Int], total: Int) -> SentenceDonutData {
        let sorted    = counts.sorted { $0.value > $1.value }
        let topItems  = sorted.prefix(4).map { SentenceDonutItem(label: $0.key, count: $0.value) }
        let otherCount = sorted.dropFirst(4).reduce(0) { $0 + $1.value }
        var items = Array(topItems)
        if otherCount > 0 {
            items.append(SentenceDonutItem(label: "기타", count: otherCount))
        }
        return SentenceDonutData(total: total, items: items)
    }
}
