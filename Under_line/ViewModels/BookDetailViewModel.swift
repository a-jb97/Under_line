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
        let viewWillAppear:    Observable<Void>      // 화면 진입 시 문장 재조회
        let deleteSentence:    Observable<Sentence>  // 삭제 버튼 탭
        let updateCurrentPage: Observable<Int>       // 페이지 기록 저장
    }

    // MARK: - Output

    struct Output {
        let sentences:    Driver<[Sentence]>  // 문장 목록
        let itemPage:     Driver<Int?>        // 책 전체 페이지 수
        let errorMessage: Signal<String>      // Toast 메시지 (1회성)
    }

    // MARK: - Dependencies

    private let book: Book
    private let sentenceRepository: SentenceRepositoryProtocol
    private let bookRepository: BookRepositoryProtocol
    private let disposeBag = DisposeBag()

    init(book: Book, sentenceRepository: SentenceRepositoryProtocol, bookRepository: BookRepositoryProtocol) {
        self.book                = book
        self.sentenceRepository  = sentenceRepository
        self.bookRepository      = bookRepository
    }

    // MARK: - Transform

    func transform(input: Input) -> Output {
        let errorMessage = PublishRelay<String>()
        let sentences    = BehaviorRelay<[Sentence]>(value: [])
        let reload       = PublishRelay<Void>()
        let itemPage     = BehaviorRelay<Int?>(value: nil)

        // 화면 최초 진입 시 책 상세(페이지 수) 조회
        input.viewWillAppear
            .take(1)
            .flatMapLatest { [weak self] _ -> Observable<Book> in
                guard let self else { return .empty() }
                return self.bookRepository.fetchBookDetail(isbn13: self.book.isbn13)
                    .asObservable()
                    .catch { _ in .empty() }
            }
            .map { $0.itemPage }
            .bind(to: itemPage)
            .disposed(by: disposeBag)

        // 화면 진입 또는 삭제 후 reload 트리거 → 문장 재조회
        Observable.merge(input.viewWillAppear, reload.asObservable())
            .flatMapLatest { [weak self] _ -> Observable<[Sentence]> in
                guard let self else { return .just([]) }
                return self.sentenceRepository.fetchSentences(for: self.book.isbn13)
                    .catch { _ in .just([]) }
                    .asObservable()
            }
            .bind(to: sentences)
            .disposed(by: disposeBag)

        // 삭제 → 완료 후 reload 신호 발행
        input.deleteSentence
            .flatMapLatest { [weak self] sentence -> Observable<Void> in
                guard let self else { return .empty() }
                return self.sentenceRepository.deleteSentence(sentence)
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

        // 페이지 기록 → DB 저장 (fire-and-forget)
        input.updateCurrentPage
            .flatMapLatest { [weak self] page -> Observable<Void> in
                guard let self else { return .empty() }
                return self.bookRepository.updateCurrentPage(isbn13: self.book.isbn13, page: page)
                    .andThen(.just(()))
                    .catch { _ in .empty() }
                    .asObservable()
            }
            .subscribe()
            .disposed(by: disposeBag)

        return Output(
            sentences:    sentences.asDriver(),
            itemPage:     itemPage.asDriver(),
            errorMessage: errorMessage.asSignal()
        )
    }
}
