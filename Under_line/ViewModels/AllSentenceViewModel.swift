//
//  AllSentenceViewModel.swift
//  Under_line
//
//  저장된 모든 문장 목록 화면 ViewModel
//

import Foundation
import RxSwift
import RxCocoa

// MARK: - AllSentenceDisplayItem

struct AllSentenceDisplayItem {
    let sentence: Sentence
    let bookTitle: String
    let bookAuthor: String
}

// MARK: - AllSentenceViewModel

final class AllSentenceViewModel {

    struct Input {
        let viewWillAppear:  Observable<Void>
        let searchQuery:     Observable<String>
        let deleteSentence:  Observable<Sentence>
    }

    struct Output {
        let items:        Driver<[AllSentenceDisplayItem]>
        let errorMessage: Signal<String>
    }

    private let sentenceRepository: SentenceRepositoryProtocol
    private let bookRepository:     BookRepositoryProtocol
    private let disposeBag = DisposeBag()

    init(
        sentenceRepository: SentenceRepositoryProtocol,
        bookRepository:     BookRepositoryProtocol
    ) {
        self.sentenceRepository = sentenceRepository
        self.bookRepository     = bookRepository
    }

    func transform(input: Input) -> Output {
        let errorMessage = PublishRelay<String>()

        // 삭제 처리
        input.deleteSentence
            .flatMapLatest { [weak self] sentence -> Observable<Void> in
                guard let self else { return .empty() }
                return rxAsync { try await self.sentenceRepository.deleteSentence(sentence) }
                    .catch { error in
                        errorMessage.accept(error.localizedDescription)
                        return .empty()
                    }
            }
            .subscribe()
            .disposed(by: disposeBag)

        // viewWillAppear마다 sentences + books를 zip해 display item 배열 생성
        let rawItems: Observable<[AllSentenceDisplayItem]> = input.viewWillAppear
            .flatMapLatest { [weak self] _ -> Observable<[AllSentenceDisplayItem]> in
                guard let self else { return .just([]) }

                let sentences = rxAsync { try await self.sentenceRepository.fetchAllSentences() }

                let books = self.bookRepository
                    .fetchSavedBooks()
                    .take(1)

                return Observable.zip(sentences, books)
                    .map { sentences, books -> [AllSentenceDisplayItem] in
                        let bookMap = Dictionary(
                            uniqueKeysWithValues: books.map { ($0.isbn13, $0) }
                        )
                        return sentences.map { sentence in
                            let book = bookMap[sentence.bookISBN]
                            return AllSentenceDisplayItem(
                                sentence:   sentence,
                                bookTitle:  book?.title  ?? "알 수 없음",
                                bookAuthor: book?.author ?? ""
                            )
                        }
                    }
                    .catch { error in
                        errorMessage.accept(error.localizedDescription)
                        return .just([])
                    }
            }
            .share(replay: 1)

        // 검색어로 책 제목 / 저자 필터링
        let filteredItems = Observable
            .combineLatest(rawItems, input.searchQuery.startWith(""))
            .map { items, query -> [AllSentenceDisplayItem] in
                guard !query.isEmpty else { return items }
                return items.filter {
                    $0.bookTitle.localizedCaseInsensitiveContains(query) ||
                    $0.bookAuthor.localizedCaseInsensitiveContains(query)
                }
            }

        return Output(
            items:        filteredItems.asDriver(onErrorJustReturn: []),
            errorMessage: errorMessage.asSignal()
        )
    }
}
