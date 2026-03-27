//
//  DirectRegisterViewModel.swift
//  Under_line
//
//  직접 도서 등록 시트 ViewModel — 폼 유효성 검사 + 저장 처리
//

import Foundation
import RxSwift
import RxCocoa

final class DirectRegisterViewModel {

    // MARK: - Input

    struct Input {
        let title:          Observable<String>
        let author:         Observable<String>
        let publisher:      Observable<String>
        let isbn:           Observable<String>
        let publishDate:    Observable<String>
        let coverURLString: Observable<String>
        let category:       Observable<String>
        let description:    Observable<String>
        let registerTap:    Observable<Void>
    }

    // MARK: - Output

    struct Output {
        let isFormValid:       Driver<Bool>    // 등록 버튼 활성화 여부
        let registerCompleted: Signal<Void>    // 등록 완료 → 시트 닫기
        let errorMessage:      Signal<String>  // Toast 메시지 (1회성)
    }

    // MARK: - Dependencies

    private let repository: BookRepositoryProtocol
    private let disposeBag = DisposeBag()

    init(repository: BookRepositoryProtocol) {
        self.repository = repository
    }

    // MARK: - Transform

    func transform(input: Input) -> Output {
        let errorMessage      = PublishRelay<String>()
        let registerCompleted = PublishRelay<Void>()

        let isFormValid = Observable.combineLatest(
            input.title,
            input.author,
            input.publisher,
            input.isbn
        ) { title, author, publisher, isbn in
            !title.trimmingCharacters(in: .whitespaces).isEmpty &&
            !author.trimmingCharacters(in: .whitespaces).isEmpty &&
            !publisher.trimmingCharacters(in: .whitespaces).isEmpty &&
            !isbn.trimmingCharacters(in: .whitespaces).isEmpty
        }
        .asDriver(onErrorJustReturn: false)

        let formData = Observable.combineLatest(
            input.title,
            input.author,
            input.publisher,
            input.isbn,
            input.publishDate,
            input.coverURLString,
            input.category,
            input.description
        )

        input.registerTap
            .withLatestFrom(formData)
            .flatMapLatest { [weak self] args -> Observable<Void> in
                guard let self else { return .empty() }
                let (title, author, publisher, isbn, publishDate, coverURLStr, categoryRaw, desc) = args

                let category = categoryRaw.trimmingCharacters(in: .whitespaces).isEmpty
                    ? "미정"
                    : categoryRaw.trimmingCharacters(in: .whitespaces)

                let coverURL: URL? = {
                    let s = coverURLStr.trimmingCharacters(in: .whitespaces)
                    return s.isEmpty ? nil : URL(string: s)
                }()

                let formattedDate: String? = {
                    let raw = publishDate.trimmingCharacters(in: .whitespaces)
                    guard raw.count == 8, raw.allSatisfy(\.isNumber) else {
                        return raw.isEmpty ? nil : raw
                    }
                    return "\(raw.prefix(4))-\(raw.dropFirst(4).prefix(2))-\(raw.suffix(2))"
                }()

                let book = Book(
                    title:       title.trimmingCharacters(in: .whitespaces),
                    author:      author.trimmingCharacters(in: .whitespaces),
                    isbn13:      isbn.trimmingCharacters(in: .whitespaces),
                    coverURL:    coverURL,
                    publisher:   publisher.trimmingCharacters(in: .whitespaces),
                    publishDate: formattedDate,
                    category:    category,
                    bestRank:    nil,
                    description: desc.trimmingCharacters(in: .whitespaces),
                    itemPage:    nil,
                    currentPage: nil
                )

                return self.repository.saveBook(book)
                    .andThen(.just(()))
                    .catch { error in
                        errorMessage.accept(error.localizedDescription)
                        return .empty()
                    }
                    .asObservable()
            }
            .bind(to: registerCompleted)
            .disposed(by: disposeBag)

        return Output(
            isFormValid:       isFormValid,
            registerCompleted: registerCompleted.asSignal(),
            errorMessage:      errorMessage.asSignal()
        )
    }
}
