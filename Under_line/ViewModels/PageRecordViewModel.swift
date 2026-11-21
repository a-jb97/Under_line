//
//  PageRecordViewModel.swift
//  Under_line
//
//  독서 진행률 편집 시트 ViewModel — 전체/현재 페이지 검증 + 저장
//

import Foundation
import RxSwift
import RxCocoa

struct ReadingProgress: Equatable {
    let itemPage: Int
    let currentPage: Int
}

enum PageRecordValidationError: LocalizedError, Equatable {
    case invalidItemPage
    case invalidCurrentPage
    case currentPageExceedsItemPage

    var errorDescription: String? {
        switch self {
        case .invalidItemPage:
            "전체 페이지는 1 이상의 숫자로 입력해주세요."
        case .invalidCurrentPage:
            "읽은 페이지는 0 이상의 숫자로 입력해주세요."
        case .currentPageExceedsItemPage:
            "전체 페이지보다 많은 페이지는 기록할 수 없습니다."
        }
    }
}

final class PageRecordViewModel {

    struct Input {
        let itemPage: Observable<String>
        let currentPage: Observable<String>
        let saveTap: Observable<Void>
    }

    struct Output {
        let isSaveEnabled: Driver<Bool>
        let saveCompleted: Signal<ReadingProgress>
        let errorMessage: Signal<String>
    }

    private let isbn13: String
    private let repository: BookRepositoryProtocol
    private let disposeBag = DisposeBag()

    init(isbn13: String, repository: BookRepositoryProtocol) {
        self.isbn13 = isbn13
        self.repository = repository
    }

    func transform(input: Input) -> Output {
        let saveCompleted = PublishRelay<ReadingProgress>()
        let errorMessage = PublishRelay<String>()
        let formData = Observable.combineLatest(input.itemPage, input.currentPage)

        let isSaveEnabled = input.itemPage
            .map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .asDriver(onErrorJustReturn: false)

        input.saveTap
            .withLatestFrom(formData)
            .compactMap { itemPageText, currentPageText -> ReadingProgress? in
                switch Self.validate(itemPage: itemPageText, currentPage: currentPageText) {
                case .success(let progress):
                    return progress
                case .failure(let error):
                    errorMessage.accept(error.localizedDescription)
                    return nil
                }
            }
            .flatMapLatest { [weak self] progress -> Observable<ReadingProgress> in
                guard let self else { return .empty() }
                return rxAsync {
                    try await self.repository.updateReadingProgress(
                        isbn13: self.isbn13,
                        itemPage: progress.itemPage,
                        currentPage: progress.currentPage
                    )
                    return progress
                }
                .catch { error in
                    errorMessage.accept(error.localizedDescription)
                    return .empty()
                }
            }
            .bind(to: saveCompleted)
            .disposed(by: disposeBag)

        return Output(
            isSaveEnabled: isSaveEnabled,
            saveCompleted: saveCompleted.asSignal(),
            errorMessage: errorMessage.asSignal()
        )
    }

    static func validate(
        itemPage itemPageText: String,
        currentPage currentPageText: String
    ) -> Result<ReadingProgress, PageRecordValidationError> {
        let normalizedItemPage = itemPageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let itemPage = Int(normalizedItemPage), itemPage > 0 else {
            return .failure(.invalidItemPage)
        }

        let normalizedCurrentPage = currentPageText.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentPage: Int
        if normalizedCurrentPage.isEmpty {
            currentPage = 0
        } else if let page = Int(normalizedCurrentPage), page >= 0 {
            currentPage = page
        } else {
            return .failure(.invalidCurrentPage)
        }

        guard currentPage <= itemPage else {
            return .failure(.currentPageExceedsItemPage)
        }
        return .success(ReadingProgress(itemPage: itemPage, currentPage: currentPage))
    }
}
