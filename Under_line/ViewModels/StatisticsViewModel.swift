//
//  StatisticsViewModel.swift
//  Under_line
//
//  통계 화면 ViewModel — 독서 세션 조회 + 장르/저자별 문장 통계
//

import Foundation
import RxSwift
import RxCocoa

// MARK: - ReadingTimeChartData

struct ReadingTimeChartPoint {
    let label: String
    let minutes: Double
}

struct ReadingTimeChartData {
    let weekly: [ReadingTimeChartPoint]
    let monthly: [ReadingTimeChartPoint]
    let yearly: [ReadingTimeChartPoint]
    let thisWeekHours: Double
    let thisMonthHours: Double
    let dailyAvgHours: Double
    static let empty = ReadingTimeChartData(
        weekly: [], monthly: [], yearly: [],
        thisWeekHours: 0, thisMonthHours: 0, dailyAvgHours: 0
    )
}

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
        let lineChartData: Driver<ReadingTimeChartData>
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
                return rxAsync { try await self.readingSessionRepository.fetchAllSessions() }
                    .catch { _ in .just([]) }
            }
            .share(replay: 1)

        let lineChartData = allSessions.map { Self.computeLineChartData(sessions: $0) }

        let donutData = input.viewWillAppear
            .flatMapLatest { [weak self] _ -> Observable<(SentenceDonutData, SentenceDonutData)> in
                guard let self else { return .just((.empty, .empty)) }
                let books     = self.bookRepository.fetchSavedBooks().take(1)
                let sentences = rxAsync { try await self.sentenceRepository.fetchAllSentences() }
                return Observable.zip(books, sentences)
                    .map { books, sentences in
                        let genreData  = Self.computeGenreData(sentences: sentences, books: books)
                        let authorData = Self.computeAuthorData(sentences: sentences, books: books)
                        return (genreData, authorData)
                    }
                    .catch { _ in .just((.empty, .empty)) }
            }

        return Output(
            allSessions:   allSessions.asDriver(onErrorJustReturn: []),
            genreData:     donutData.map { $0.0 }.asDriver(onErrorJustReturn: .empty),
            authorData:    donutData.map { $0.1 }.asDriver(onErrorJustReturn: .empty),
            lineChartData: lineChartData.asDriver(onErrorJustReturn: .empty)
        )
    }

    // MARK: - Private helpers

    private static func computeLineChartData(sessions: [ReadingSession]) -> ReadingTimeChartData {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ko_KR")
        calendar.firstWeekday = 2  // 월요일 기준
        let now = Date()

        let weekStart  = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let yearStart  = calendar.date(from: calendar.dateComponents([.year], from: now)) ?? now

        // 주간: 월~일 7일
        let weekDays = ["월", "화", "수", "목", "금", "토", "일"]
        let weeklyPoints: [ReadingTimeChartPoint] = (0..<7).map { offset in
            let dayStart = calendar.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
            let dayEnd   = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            let secs = sessions.filter { $0.date >= dayStart && $0.date < dayEnd }
                .reduce(0) { $0 + $1.durationSeconds }
            return ReadingTimeChartPoint(label: weekDays[offset], minutes: Double(secs) / 60)
        }

        // 월간: 7일 단위 블록으로 묶음
        let daysInMonth = calendar.range(of: .day, in: .month, for: monthStart)!.count
        let weeksInMonth = Int(ceil(Double(daysInMonth) / 7.0))
        let monthlyPoints: [ReadingTimeChartPoint] = (0..<weeksInMonth).map { weekIndex in
            let startDay = weekIndex * 7
            let endDay   = min(startDay + 7, daysInMonth)
            let blockStart = calendar.date(byAdding: .day, value: startDay, to: monthStart) ?? monthStart
            let blockEnd   = calendar.date(byAdding: .day, value: endDay,   to: monthStart) ?? monthStart
            let secs = sessions.filter { $0.date >= blockStart && $0.date < blockEnd }
                .reduce(0) { $0 + $1.durationSeconds }
            return ReadingTimeChartPoint(label: "\(weekIndex + 1)주", minutes: Double(secs) / 60)
        }

        // 연간: 1~12월
        let yearlyPoints: [ReadingTimeChartPoint] = (0..<12).map { monthOffset in
            var comps = calendar.dateComponents([.year], from: yearStart)
            comps.month = monthOffset + 1
            let mStart = calendar.date(from: comps) ?? yearStart
            let mEnd   = calendar.date(byAdding: .month, value: 1, to: mStart) ?? mStart
            let secs = sessions.filter { $0.date >= mStart && $0.date < mEnd }
                .reduce(0) { $0 + $1.durationSeconds }
            return ReadingTimeChartPoint(label: "\(monthOffset + 1)월", minutes: Double(secs) / 60)
        }

        // 통계 값
        let weekEnd  = calendar.date(byAdding: .day,   value: 7, to: weekStart) ?? weekStart
        let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        let weekSecs  = sessions.filter { $0.date >= weekStart  && $0.date < weekEnd  }.reduce(0) { $0 + $1.durationSeconds }
        let monthSecs = sessions.filter { $0.date >= monthStart && $0.date < monthEnd }.reduce(0) { $0 + $1.durationSeconds }

        let thirtyAgo    = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        let last30Secs   = sessions.filter { $0.date >= thirtyAgo }.reduce(0) { $0 + $1.durationSeconds }
        let dailyAvgSecs = Double(last30Secs) / 30.0

        return ReadingTimeChartData(
            weekly:         weeklyPoints,
            monthly:        monthlyPoints,
            yearly:         yearlyPoints,
            thisWeekHours:  Double(weekSecs)  / 3600,
            thisMonthHours: Double(monthSecs) / 3600,
            dailyAvgHours:  dailyAvgSecs      / 3600
        )
    }

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
