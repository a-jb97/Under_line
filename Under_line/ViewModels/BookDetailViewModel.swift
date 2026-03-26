//
//  BookDetailViewModel.swift
//  Under_line
//
//  도서 상세 화면 ViewModel — 문장 목록 fetch + 삭제 처리
//

import Foundation
import RxSwift
import RxCocoa

final class BookDetailViewModel {

    // MARK: - Input

    struct Input {
        let viewWillAppear:   Observable<Void>      // 화면 진입 시 문장 재조회
        let deleteSentence:   Observable<Sentence>  // 삭제 버튼 탭
    }

    // MARK: - Output

    struct Output {
        let sentences:    Driver<[Sentence]>  // 문장 목록
        let errorMessage: Signal<String>      // Toast 메시지 (1회성)
    }

    // MARK: - Dependencies

    private let book: Book
    private let repository: SentenceRepositoryProtocol
    private let disposeBag = DisposeBag()

    init(book: Book, repository: SentenceRepositoryProtocol) {
        self.book       = book
        self.repository = repository
    }

    // MARK: - Transform

    func transform(input: Input) -> Output {
        let errorMessage = PublishRelay<String>()
        let sentences    = BehaviorRelay<[Sentence]>(value: [])
        let reload       = PublishRelay<Void>()

        // 화면 진입 또는 삭제 후 reload 트리거 → 문장 재조회
        Observable.merge(input.viewWillAppear, reload.asObservable())
            .flatMapLatest { [weak self] _ -> Observable<[Sentence]> in
                guard let self else { return .just([]) }
                return self.repository.fetchSentences(for: self.book.isbn13)
                    .catch { _ in .just([]) }
                    .asObservable()
            }
            .bind(to: sentences)
            .disposed(by: disposeBag)

        // 삭제 → 완료 후 reload 신호 발행
        input.deleteSentence
            .flatMapLatest { [weak self] sentence -> Observable<Void> in
                guard let self else { return .empty() }
                return self.repository.deleteSentence(sentence)
                    .andThen(.just(()))
                    .catch { error in
                        errorMessage.accept(error.localizedDescription)
                        return .empty()
                    }
                    .asObservable()
            }
            .map { }
            .bind(to: reload)
            .disposed(by: disposeBag)

        return Output(
            sentences:    sentences.asDriver(),
            errorMessage: errorMessage.asSignal()
        )
    }
}
