//
//  BookshelfViewModel.swift
//  Under_line
//
//  책장 화면 ViewModel — 저장된 도서 목록 스트림 + 삭제 처리
//

import Foundation
import RxSwift
import RxCocoa

final class BookshelfViewModel {

    // MARK: - Input

    struct Input {
        let deleteBook:   Observable<Book>     // 삭제 버튼 탭
        let deleteAll:    Observable<Void>     // 전부 삭제 버튼 탭
        let reorderBooks: Observable<[String]> // 드래그로 재정렬된 ISBN 배열
    }

    // MARK: - Output

    struct Output {
        let books:        Driver<[Book]>   // 저장된 도서 목록 (자동 갱신)
        let errorMessage: Signal<String>   // Toast 메시지 (1회성)
    }

    // MARK: - Dependencies

    private let repository: BookRepositoryProtocol
    private let disposeBag = DisposeBag()

    init(repository: BookRepositoryProtocol) {
        self.repository = repository
    }

    // MARK: - Transform

    func transform(input: Input) -> Output {
        let errorMessage = PublishRelay<String>()

        input.deleteBook
            .flatMapLatest { [weak self] book -> Observable<Void> in
                guard let self else { return .empty() }
                return self.repository.deleteBook(book)
                    .andThen(.just(()))
                    .catch { error in
                        errorMessage.accept(error.localizedDescription)
                        return .empty()
                    }
                    .asObservable()
            }
            .subscribe()
            .disposed(by: disposeBag)

        input.deleteAll
            .flatMapLatest { [weak self] _ -> Observable<Void> in
                guard let self else { return .empty() }
                return self.repository.deleteAllBooks()
                    .andThen(.just(()))
                    .catch { error in
                        errorMessage.accept(error.localizedDescription)
                        return .empty()
                    }
                    .asObservable()
            }
            .subscribe()
            .disposed(by: disposeBag)

        input.reorderBooks
            .flatMapLatest { [weak self] isbns -> Observable<Void> in
                guard let self else { return .empty() }
                return self.repository.reorderBooks(orderedISBNs: isbns)
                    .andThen(.just(()))
                    .catch { _ in .empty() }
                    .asObservable()
            }
            .subscribe()
            .disposed(by: disposeBag)

        return Output(
            books:        repository.fetchSavedBooks().asDriver(onErrorJustReturn: []),
            errorMessage: errorMessage.asSignal()
        )
    }
}
