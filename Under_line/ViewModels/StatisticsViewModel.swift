//
//  StatisticsViewModel.swift
//  Under_line
//
//  통계 화면 ViewModel — 전체 독서 세션 조회
//

import Foundation
import RxSwift
import RxCocoa

final class StatisticsViewModel {

    // MARK: - Input

    struct Input {
        let viewWillAppear: Observable<Void>
    }

    // MARK: - Output

    struct Output {
        let allSessions: Driver<[ReadingSession]>
    }

    // MARK: - Dependencies

    private let readingSessionRepository: ReadingSessionRepositoryProtocol
    private let disposeBag = DisposeBag()

    init(readingSessionRepository: ReadingSessionRepositoryProtocol) {
        self.readingSessionRepository = readingSessionRepository
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

        return Output(allSessions: allSessions.asDriver(onErrorJustReturn: []))
    }
}
