//
//  ReadingRecordViewModel.swift
//  Under_line
//
//  독서 기록 화면 ViewModel — 세션 저장, 차트 데이터 집계, 페이지 기록 저장
//

import Foundation
import RxSwift
import RxCocoa

// MARK: - Supporting Types

struct ChartPoint {
    let label: String
    let seconds: Int
}

enum ChartPeriod {
    case daily, weekly, monthly
}

// MARK: - ReadingRecordViewModel

final class ReadingRecordViewModel {

    // MARK: - Input

    struct Input {
        let viewDidAppear: Observable<Void>
        let tabSelected:   Observable<Int>   // 0=일별, 1=주별, 2=월별
        let timerStopped:  Observable<Int>   // 경과 초
        let pageRecorded:  Observable<Int>   // 기록된 페이지 번호
    }

    // MARK: - Output

    struct Output {
        let chartPoints: Driver<[ChartPoint]>
    }

    // MARK: - Dependencies

    private let book: Book
    private let readingSessionRepository: ReadingSessionRepositoryProtocol
    private let bookRepository: BookRepositoryProtocol
    private let disposeBag = DisposeBag()

    init(
        book: Book,
        readingSessionRepository: ReadingSessionRepositoryProtocol,
        bookRepository: BookRepositoryProtocol
    ) {
        self.book = book
        self.readingSessionRepository = readingSessionRepository
        self.bookRepository = bookRepository
    }

    // MARK: - Transform

    func transform(input: Input) -> Output {
        let reloadTrigger = PublishRelay<Void>()

        // 타이머 종료 → 세션 저장 → 차트 리로드 트리거
        input.timerStopped
            .flatMapLatest { [weak self] elapsed -> Observable<Void> in
                guard let self else { return .empty() }
                return rxAsync { try await self.readingSessionRepository.saveSession(bookISBN: self.book.isbn13, durationSeconds: elapsed) }
                    .catch { _ in .empty() }
            }
            .map { }
            .bind(to: reloadTrigger)
            .disposed(by: disposeBag)

        // 페이지 기록 → DB 저장 (fire-and-forget)
        input.pageRecorded
            .flatMapLatest { [weak self] page -> Observable<Void> in
                guard let self else { return .empty() }
                return rxAsync { try await self.bookRepository.updateCurrentPage(isbn13: self.book.isbn13, page: page) }
                    .catch { _ in .empty() }
            }
            .subscribe()
            .disposed(by: disposeBag)

        // 기간 스트림 (초기값: 일별)
        let period = input.tabSelected
            .startWith(0)
            .map { idx -> ChartPeriod in [.daily, .weekly, .monthly][idx] }

        // 화면 진입 또는 세션 저장 완료 시 → 현재 기간으로 차트 재조회
        let fetchTrigger = Observable.merge(input.viewDidAppear, reloadTrigger.asObservable())

        let chartPoints = Observable
            .combineLatest(fetchTrigger, period) { _, period in period }
            .flatMapLatest { [weak self] period -> Observable<[ChartPoint]> in
                guard let self else { return .just([]) }
                return rxAsync { try await self.readingSessionRepository.fetchSessions(for: self.book.isbn13) }
                    .map { ReadingRecordViewModel.aggregate(sessions: $0, period: period) }
                    .catch { _ in .just([]) }
            }

        return Output(chartPoints: chartPoints.asDriver(onErrorJustReturn: []))
    }

    // MARK: - Data Aggregation

    static func aggregate(sessions: [ReadingSession], period: ChartPeriod) -> [ChartPoint] {
        let calendar = Calendar.current
        let now = Date()

        switch period {
        case .daily:
            return (0..<7).reversed().map { daysAgo -> ChartPoint in
                let date     = calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
                let dayStart = calendar.startOfDay(for: date)
                let dayEnd   = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
                let total    = sessions
                    .filter { $0.date >= dayStart && $0.date < dayEnd }
                    .reduce(0) { $0 + $1.durationSeconds }
                let weekday = calendar.component(.weekday, from: date)
                let label   = ["일","월","화","수","목","금","토"][weekday - 1]
                return ChartPoint(label: label, seconds: total)
            }

        case .weekly:
            return (0..<7).reversed().map { weeksAgo -> ChartPoint in
                let ref       = calendar.date(byAdding: .weekOfYear, value: -weeksAgo, to: now) ?? now
                let interval  = calendar.dateInterval(of: .weekOfYear, for: ref)
                let weekStart = interval?.start ?? now
                let weekEnd   = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart) ?? weekStart
                let total     = sessions
                    .filter { $0.date >= weekStart && $0.date < weekEnd }
                    .reduce(0) { $0 + $1.durationSeconds }
                let labelDate = weeksAgo == 0 ? now : weekStart
                let month = calendar.component(.month, from: labelDate)
                let day   = calendar.component(.day, from: labelDate)
                return ChartPoint(label: "\(month)/\(day)", seconds: total)
            }

        case .monthly:
            return (0..<7).reversed().map { monthsAgo -> ChartPoint in
                let ref        = calendar.date(byAdding: .month, value: -monthsAgo, to: now) ?? now
                let comps      = calendar.dateComponents([.year, .month], from: ref)
                let monthStart = calendar.date(from: comps) ?? now
                let monthEnd   = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
                let total      = sessions
                    .filter { $0.date >= monthStart && $0.date < monthEnd }
                    .reduce(0) { $0 + $1.durationSeconds }
                return ChartPoint(label: "\(comps.month ?? 0)월", seconds: total)
            }
        }
    }
}
