//
//  BookSearchViewModel.swift
//  Under_line
//
//  도서 검색 시트 ViewModel — MVVM Input/Output 패턴 (페이지네이션 지원)
//

import RxSwift
import RxCocoa
import Foundation

final class BookSearchViewModel {

    // MARK: - Input

    struct Input {
        let viewDidLoad:    Observable<Void>    // 베스트셀러 fetch 트리거
        let searchQuery:    Observable<String>  // searchTextField 텍스트 스트림
        let searchTrigger:  Observable<Void>    // return 키 탭
        let loadNextPage:   Observable<Void>    // 스크롤 하단 도달 시
        let registerBook:   Observable<Book>    // 등록 버튼 탭
    }

    // MARK: - Output

    struct Output {
        let books:             Driver<[Book]>   // UITableView 데이터 (누적)
        let isLoading:         Driver<Bool>     // 초기 로딩 인디케이터
        let isLoadingMore:     Driver<Bool>     // 추가 페이지 로딩 인디케이터
        let errorMessage:      Signal<String>   // Toast 메시지 (1회성)
        let registerCompleted: Signal<Void>     // 등록 완료 → 시트 닫기
    }

    // MARK: - Dependencies

    private let repository: BookRepositoryProtocol
    private let disposeBag = DisposeBag()

    init(repository: BookRepositoryProtocol) {
        self.repository = repository
    }

    // MARK: - Transform

    func transform(input: Input) -> Output {
        let isLoading     = BehaviorRelay<Bool>(value: false)
        let isLoadingMore = BehaviorRelay<Bool>(value: false)
        let errorMessage  = PublishRelay<String>()
        let latestQuery   = BehaviorRelay<String>(value: "")
        let currentPage   = BehaviorRelay<Int>(value: 1)
        let hasMorePages  = BehaviorRelay<Bool>(value: false)
        let books         = BehaviorRelay<[Book]>(value: [])

        // 검색어 최신값 유지
        input.searchQuery
            .bind(to: latestQuery)
            .disposed(by: disposeBag)

        // 베스트셀러 — viewDidLoad 시 1회, 페이지네이션 없음
        input.viewDidLoad
            .flatMapLatest { [weak self] _ -> Observable<[Book]> in
                guard let self else { return .empty() }
                isLoading.accept(true)
                return self.repository.fetchBestsellers()
                    .do(
                        onSuccess: { _ in isLoading.accept(false) },
                        onError:   { _ in isLoading.accept(false) }
                    )
                    .catch { error in
                        errorMessage.accept(error.localizedDescription)
                        return .just([])
                    }
                    .asObservable()
            }
            .subscribe(onNext: { fetched in
                books.accept(fetched)
                currentPage.accept(1)
                hasMorePages.accept(false)
            })
            .disposed(by: disposeBag)

        // 새 검색 — return 키 탭 시 1페이지부터 다시 시작
        input.searchTrigger
            .withLatestFrom(latestQuery)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .do(onNext: { _ in
                currentPage.accept(1)
                hasMorePages.accept(true)
            })
            .flatMapLatest { [weak self] query -> Observable<[Book]> in
                guard let self else { return .empty() }
                isLoading.accept(true)
                return self.repository.searchBooks(query: query, page: 1)
                    .do(
                        onSuccess: { _ in isLoading.accept(false) },
                        onError:   { _ in isLoading.accept(false) }
                    )
                    .catch { error in
                        errorMessage.accept(error.localizedDescription)
                        return .just([])
                    }
                    .asObservable()
            }
            .subscribe(onNext: { fetched in
                books.accept(fetched)
                // 50개 미만이면 마지막 페이지
                if fetched.count < 50 { hasMorePages.accept(false) }
            })
            .disposed(by: disposeBag)

        // 다음 페이지 — 스크롤 하단 도달 시 (중복 요청 방지 + 쿼리 일치 확인)
        input.loadNextPage
            .withLatestFrom(Observable.combineLatest(
                isLoadingMore.asObservable(),
                isLoading.asObservable(),
                hasMorePages.asObservable(),
                latestQuery.asObservable(),
                currentPage.asObservable()
            ))
            .filter { isMore, isLoad, hasMore, query, _ in
                !isMore && !isLoad && hasMore
                    && !query.trimmingCharacters(in: .whitespaces).isEmpty
            }
            .map { _, _, _, query, page in (query, page + 1) }
            .flatMap { [weak self] (query, nextPage) -> Observable<(String, Int, [Book])> in
                guard let self else { return .empty() }
                isLoadingMore.accept(true)
                return self.repository.searchBooks(query: query, page: nextPage)
                    .do(
                        onSuccess: { _ in isLoadingMore.accept(false) },
                        onError:   { _ in isLoadingMore.accept(false) }
                    )
                    .catch { error in
                        errorMessage.accept(error.localizedDescription)
                        return .just([])
                    }
                    .map { (query, nextPage, $0) }
                    .asObservable()
            }
            .subscribe(onNext: { query, nextPage, fetched in
                // 검색어가 바뀐 경우 무시 (스테일 응답 방어)
                guard latestQuery.value == query else { return }
                currentPage.accept(nextPage)
                books.accept(books.value + fetched)
                if fetched.count < 50 { hasMorePages.accept(false) }
            })
            .disposed(by: disposeBag)

        // 등록 버튼 탭 → saveBook → registerCompleted
        let registerCompleted = PublishRelay<Void>()

        input.registerBook
            .flatMapLatest { [weak self] book -> Observable<Void> in
                guard let self else { return .empty() }
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
            books:             books.asDriver(),
            isLoading:         isLoading.asDriver(),
            isLoadingMore:     isLoadingMore.asDriver(),
            errorMessage:      errorMessage.asSignal(),
            registerCompleted: registerCompleted.asSignal()
        )
    }
}
