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
        let isLoading            = BehaviorRelay<Bool>(value: false)
        let isLoadingMore        = BehaviorRelay<Bool>(value: false)
        let errorMessage         = PublishRelay<String>()
        let latestQuery          = BehaviorRelay<String>(value: "")
        let currentPage          = BehaviorRelay<Int>(value: 1)
        let hasMorePages         = BehaviorRelay<Bool>(value: false)
        let books                = BehaviorRelay<[Book]>(value: [])
        // 이미 요청을 보낸 가장 높은 페이지 번호 — 동기적으로 설정해 중복 요청 차단
        let highestRequestedPage = BehaviorRelay<Int>(value: 0)
        // 검색 결과의 totalResults 기반으로 계산한 실제 최대 페이지
        // Aladin API 한계: 페이지당 50개, 총 최대 200개 → 최대 4페이지
        let effectiveMaxPage     = BehaviorRelay<Int>(value: 4)
        // 현재 검색어의 실제 결과 수 — 누적 시 이 수만큼 잘라 중복 방지
        let totalResultCount     = BehaviorRelay<Int>(value: 0)

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
                highestRequestedPage.accept(0)
                hasMorePages.accept(false)
            })
            .flatMapLatest { [weak self] query -> Observable<(books: [Book], totalResults: Int)> in
                guard let self else { return .empty() }
                isLoading.accept(true)
                return self.repository.searchBooks(query: query, page: 1)
                    .do(
                        onSuccess: { _ in isLoading.accept(false) },
                        onError:   { _ in isLoading.accept(false) }
                    )
                    .catch { error in
                        errorMessage.accept(error.localizedDescription)
                        return .just((books: [], totalResults: 0))
                    }
                    .asObservable()
            }
            .subscribe(onNext: { result in
                // totalResults 기반으로 실제 페이지 수 계산 (API 한계 200개 = 4페이지 상한)
                let cappedTotal = min(result.totalResults, 200)
                let pages = cappedTotal == 0 ? 1 : Int(ceil(Double(cappedTotal) / 50.0))
                effectiveMaxPage.accept(pages)
                totalResultCount.accept(cappedTotal)
                books.accept(result.books)
                hasMorePages.accept(result.totalResults > result.books.count)
            })
            .disposed(by: disposeBag)

        // 다음 페이지 — 스크롤 하단 도달 시
        // highestRequestedPage: 요청 시작 즉시(동기) 갱신 → Driver 비동기 UI 업데이트 후
        // willDisplayCell이 재발동해도 같은 페이지를 중복 요청하지 않음
        input.loadNextPage
            .withLatestFrom(Observable.combineLatest(
                isLoading.asObservable(),
                hasMorePages.asObservable(),
                latestQuery.asObservable(),
                currentPage.asObservable(),
                highestRequestedPage.asObservable(),
                effectiveMaxPage.asObservable()
            ))
            .filter { isLoad, hasMore, query, page, highReq, maxPg in
                let nextPage = page + 1
                return !isLoad && hasMore
                    && !query.trimmingCharacters(in: .whitespaces).isEmpty
                    && nextPage > highReq
                    && nextPage <= maxPg
            }
            .map { _, _, query, page, _, _ in (query, page + 1) }
            .do(onNext: { _, nextPage in
                // 동기적으로 선점 — 이후 중복 이벤트는 위 filter에서 차단됨
                highestRequestedPage.accept(nextPage)
                isLoadingMore.accept(true)
            })
            .flatMap { [weak self] (query, nextPage) -> Observable<(String, Int, [Book])> in
                guard let self else { return .empty() }
                return self.repository.searchBooks(query: query, page: nextPage)
                    .do(onError: { _ in isLoadingMore.accept(false) })
                    .catch { error in
                        errorMessage.accept(error.localizedDescription)
                        return .just((books: [], totalResults: 0))
                    }
                    .map { (query, nextPage, $0.books) }
                    .asObservable()
            }
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { query, nextPage, fetched in
                // 검색어가 바뀐 경우 무시 (스테일 응답 방어)
                guard latestQuery.value == query else {
                    isLoadingMore.accept(false)
                    return
                }
                currentPage.accept(nextPage)
                if !fetched.isEmpty {
                    let combined = Array((books.value + fetched).prefix(totalResultCount.value))
                    books.accept(combined)
                    let reachedEnd = combined.count >= totalResultCount.value
                        || fetched.count < 50
                        || nextPage >= effectiveMaxPage.value
                    if reachedEnd { hasMorePages.accept(false) }
                } else {
                    hasMorePages.accept(false)
                }
                isLoadingMore.accept(false)
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
