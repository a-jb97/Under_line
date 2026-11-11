import XCTest
import RxSwift
import RxCocoa
import UIKit
@testable import Under_line

@MainActor
final class BookSearchViewModelTests: XCTestCase {
    func test_registeredISBNs_initialSnapshotAndChangesBlockOnlySavedBooks() async {
        let books = makeBooks(0..<2)
        let h = Harness(savedBooks: [books[0]])
        h.repository.holdsRegistrations = true
        XCTAssertEqual(h.registeredISBNs, ["0"])

        h.register.onNext(books[0])
        await drain()
        XCTAssertTrue(h.repository.registrations.isEmpty)
        h.register.onNext(books[1])
        await drain()
        XCTAssertEqual(h.repository.registrations.count, 1)
        h.repository.registrations[0].continuation.resume()
        await drain()
        await drain()

        h.repository.savedBooks.accept([])
        XCTAssertTrue(h.registeredISBNs.isEmpty)
        h.register.onNext(books[0])
        await drain()
        XCTAssertEqual(h.repository.registrations.count, 2)
        h.repository.registrations[1].continuation.resume()
        await drain()
        await drain()
    }

    func test_registeredCell_filledIconBlocksRegistrationAndKeepsWishlistIndependent() throws {
        let cell = BookRowCell(style: .default, reuseIdentifier: BookRowCell.reuseID)
        let books = makeBooks(0..<2)
        var wishlist = BookSearchViewModel.WishlistState()
        wishlist.isLoaded = true
        cell.configure(book: books[0], displayScale: 1, descriptionWidth: 272,
                       isExpanded: false, isDescriptionLoading: false,
                       wishlistState: wishlist, registeredISBNs: ["0"])
        let register = try XCTUnwrap(findButton(in: cell, identifier: "registerBookButton"))
        let heart = try XCTUnwrap(findButton(in: cell, identifier: "wishlistButton"))
        XCTAssertTrue(register.isSelected)
        XCTAssertFalse(register.isEnabled)
        XCTAssertEqual(register.accessibilityLabel, "이미 등록된 도서")
        XCTAssertTrue(heart.isEnabled)
        XCTAssertFalse(heart.isSelected)
        var registered: [String] = []
        cell.onPrimaryAction = { registered.append($0) }
        register.sendActions(for: .touchUpInside)
        XCTAssertTrue(registered.isEmpty)

        cell.setRegistrationState([])
        XCTAssertFalse(register.isSelected)
        XCTAssertTrue(register.isEnabled)
        register.sendActions(for: .touchUpInside)
        XCTAssertEqual(registered, ["0"])
        cell.prepareForReuse()
        XCTAssertFalse(register.isEnabled)
        cell.configure(book: books[1], displayScale: 1, descriptionWidth: 272,
                       isExpanded: false, isDescriptionLoading: false,
                       wishlistState: wishlist, registeredISBNs: ["0"])
        XCTAssertFalse(register.isSelected)
        XCTAssertTrue(register.isEnabled)
        XCTAssertEqual(register.accessibilityValue, "등록 안 됨")
    }

    func test_wishlistAppearance_loadsExistingISBNsAndRefreshesOnReentry() async {
        let h = Harness()
        h.wishlistRepository.savedISBNs = ["0"]
        h.appeared.onNext(())
        await drain()
        await drain()
        XCTAssertTrue(h.wishlistState.isLoaded)
        XCTAssertEqual(h.wishlistState.savedISBNs, ["0"])
        h.wishlistRepository.savedISBNs = ["1"]

        h.appeared.onNext(())
        await drain()
        await drain()

        XCTAssertEqual(h.wishlistState.savedISBNs, ["1"])
        XCTAssertEqual(h.wishlistRepository.fetchCount, 2)
    }

    func test_wishlistTap_addsAndDeletesWithoutCompletingRegistration() async {
        let h = Harness()
        h.appeared.onNext(())
        await drain()
        await drain()
        let book = makeBooks(0..<1)[0]

        h.wishlistTap.onNext(book)
        await drain()
        await drain()
        XCTAssertEqual(h.wishlistState.savedISBNs, [book.isbn13])
        XCTAssertEqual(h.wishlistRepository.addedBooks.map(\.isbn13), [book.isbn13])
        XCTAssertEqual(h.wishlistMessages, ["위시리스트에 추가했습니다."])
        h.wishlistTap.onNext(book)
        await drain()
        await drain()
        XCTAssertTrue(h.wishlistState.savedISBNs.isEmpty)
        XCTAssertEqual(h.wishlistRepository.deletedISBNs, [book.isbn13])
        XCTAssertEqual(h.wishlistMessages.last, "위시리스트에서 삭제했습니다.")
        XCTAssertEqual(h.registrationCompletedCount, 0)
        XCTAssertTrue(h.repository.registrations.isEmpty)
    }

    func test_wishlistTap_ignoresSameISBNWhileAllowingAnotherBook() async {
        let h = Harness()
        h.appeared.onNext(())
        await drain()
        await drain()
        h.wishlistRepository.holdsMutations = true
        let books = makeBooks(0..<2)

        h.wishlistTap.onNext(books[0])
        h.wishlistTap.onNext(books[0])
        h.wishlistTap.onNext(books[1])
        await drain()
        await drain()
        XCTAssertEqual(h.wishlistRepository.addedBooks.map(\.isbn13), ["0", "1"])
        XCTAssertEqual(h.wishlistState.pendingISBNs, ["0", "1"])
        for continuation in h.wishlistRepository.mutations { continuation.resume() }
        await drain()
        await drain()
        XCTAssertEqual(h.wishlistState.savedISBNs, ["0", "1"])
        XCTAssertTrue(h.wishlistState.pendingISBNs.isEmpty)
    }

    func test_wishlistFailure_preservesPriorStateAndAllowsRetry() async {
        let h = Harness()
        h.appeared.onNext(())
        await drain()
        await drain()
        let book = makeBooks(0..<1)[0]
        h.wishlistRepository.mutationError = StubError.failed
        h.wishlistTap.onNext(book)
        await drain()
        await drain()
        XCTAssertTrue(h.wishlistState.savedISBNs.isEmpty)
        XCTAssertTrue(h.wishlistState.pendingISBNs.isEmpty)
        XCTAssertEqual(h.errors.count, 1)
        XCTAssertTrue(h.wishlistMessages.isEmpty)

        h.wishlistRepository.mutationError = nil
        h.wishlistTap.onNext(book)
        await drain()
        await drain()
        h.wishlistRepository.mutationError = StubError.failed
        h.wishlistTap.onNext(book)
        await drain()
        await drain()
        XCTAssertEqual(h.wishlistState.savedISBNs, [book.isbn13])
        XCTAssertTrue(h.wishlistState.pendingISBNs.isEmpty)
        XCTAssertEqual(h.errors.count, 2)
    }

    func test_wishlistDuplicate_synchronizesSavedStateWithoutDeleting() async {
        let h = Harness()
        h.appeared.onNext(())
        await drain()
        await drain()
        h.wishlistRepository.mutationError = WishlistRepositoryError.duplicateISBN13

        h.wishlistTap.onNext(makeBooks(0..<1)[0])
        await drain()
        await drain()

        XCTAssertEqual(h.wishlistState.savedISBNs, ["0"])
        XCTAssertTrue(h.wishlistRepository.deletedISBNs.isEmpty)
        XCTAssertTrue(h.errors.isEmpty)
        XCTAssertEqual(h.wishlistMessages, ["이미 위시리스트에 추가된 도서입니다."])
    }

    func test_wishlistTap_normalizesISBNForStateAndDeletion() async {
        let h = Harness()
        h.wishlistRepository.savedISBNs = ["9788937460586"]
        h.appeared.onNext(())
        await drain()
        await drain()
        let book = Book(
            title: "책", author: "저자", isbn13: " \n9788937460586\t", coverURL: nil,
            publisher: "출판사", publishDate: nil, category: nil, bestRank: nil,
            description: "소개", itemPage: nil, currentPage: nil
        )

        h.wishlistTap.onNext(book)
        await drain()
        await drain()

        XCTAssertEqual(h.wishlistRepository.deletedISBNs, ["9788937460586"])
        XCTAssertTrue(h.wishlistRepository.addedBooks.isEmpty)
        XCTAssertTrue(h.wishlistState.savedISBNs.isEmpty)
    }

    func test_wishlistFetchFailure_blocksTapsUntilSuccessfulReentry() async {
        let h = Harness()
        let book = makeBooks(0..<1)[0]
        h.wishlistTap.onNext(book)
        h.wishlistRepository.fetchError = StubError.failed
        h.appeared.onNext(())
        await drain()
        await drain()
        h.wishlistTap.onNext(book)
        await drain()
        XCTAssertFalse(h.wishlistState.isLoaded)
        XCTAssertFalse(h.wishlistState.isRefreshing)
        XCTAssertTrue(h.wishlistRepository.addedBooks.isEmpty)
        XCTAssertEqual(h.errors.count, 1)

        h.wishlistRepository.fetchError = nil
        h.appeared.onNext(())
        await drain()
        await drain()
        XCTAssertTrue(h.wishlistState.isLoaded)
    }

    func test_wishlistRefresh_ignoresCancelledOlderSnapshot() async {
        let h = Harness()
        h.wishlistRepository.holdsFetches = true
        h.appeared.onNext(())
        await drain()
        h.appeared.onNext(())
        await drain()
        XCTAssertEqual(h.wishlistRepository.fetches.count, 2)
        h.wishlistRepository.fetches[1].resume(returning: [wishlistItem(isbn13: "1")])
        await drain()
        await drain()
        h.wishlistRepository.fetches[0].resume(returning: [wishlistItem(isbn13: "0")])
        await drain()
        await drain()
        XCTAssertEqual(h.wishlistState.savedISBNs, ["1"])
    }

    func test_wishlistReentry_duringMutationRefreshesAfterSaving() async {
        let h = Harness()
        h.appeared.onNext(())
        await drain()
        await drain()
        h.wishlistRepository.holdsMutations = true
        h.wishlistTap.onNext(makeBooks(0..<1)[0])
        await drain()
        h.appeared.onNext(())
        XCTAssertEqual(h.wishlistRepository.fetchCount, 1)

        h.wishlistRepository.mutations[0].resume()
        await drain()
        await drain()
        await drain()

        XCTAssertEqual(h.wishlistRepository.fetchCount, 2)
        XCTAssertEqual(h.wishlistState.savedISBNs, ["0"])
        XCTAssertFalse(h.wishlistState.isRefreshing)
    }

    func test_wishlistState_survivesSearchListSwitchAndPagination() async {
        let h = Harness()
        h.wishlistRepository.savedISBNs = ["0"]
        h.appeared.onNext(())
        await drain()
        await drain()
        let first = await requested(h) { h.search("책") }
        await finish(first, .success((makeBooks(0..<50), 100)))
        let next = await requested(h) { h.next.onNext(()) }
        await finish(next, .success((makeBooks(50..<100), 100)))
        let list = await requested(h) { h.list.onNext(.trending) }
        await finish(list, .success((makeBooks(0..<1), 1)))

        XCTAssertEqual(h.wishlistState.savedISBNs, ["0"])
        XCTAssertEqual(h.wishlistRepository.fetchCount, 1)
    }

    func test_wishlistCell_reuseResetsStateAndTapUsesCurrentBook() throws {
        let cell = BookRowCell(style: .default, reuseIdentifier: BookRowCell.reuseID)
        let books = makeBooks(0..<2)
        var state = BookSearchViewModel.WishlistState()
        state.isLoaded = true
        state.savedISBNs = ["0"]
        cell.configure(book: books[0], displayScale: 1, descriptionWidth: 272,
                       isExpanded: false, isDescriptionLoading: false, wishlistState: state)
        let heart = try XCTUnwrap(findButton(in: cell, identifier: "wishlistButton"))
        XCTAssertTrue(heart.isSelected)
        XCTAssertEqual(heart.accessibilityLabel, "위시리스트에서 삭제")
        var tapped: [String] = []
        cell.onToggleWishlist = { tapped.append($0) }
        cell.prepareForReuse()
        XCTAssertFalse(heart.isSelected)
        XCTAssertFalse(heart.isEnabled)
        XCTAssertNil(cell.onToggleWishlist)

        cell.configure(book: books[1], displayScale: 1, descriptionWidth: 272,
                       isExpanded: true, isDescriptionLoading: false, wishlistState: state)
        cell.onToggleWishlist = { tapped.append($0) }
        heart.sendActions(for: .touchUpInside)
        XCTAssertEqual(tapped, ["1"])
        XCTAssertFalse(heart.isSelected)
        XCTAssertEqual(heart.accessibilityLabel, "위시리스트에 추가")
        state.pendingISBNs = ["1"]
        cell.setWishlistState(state)
        XCTAssertFalse(heart.isEnabled)
        heart.sendActions(for: .touchUpInside)
        XCTAssertEqual(tapped, ["1"])
    }

    func test_wishlistCell_narrowLayoutPositionsHeartBelowRegistrationWithTouchArea() throws {
        let cell = BookRowCell(style: .default, reuseIdentifier: BookRowCell.reuseID)
        var state = BookSearchViewModel.WishlistState()
        state.isLoaded = true
        let book = Book(
            title: "긴 제목을 가진 도서의 검색 결과에서 두 줄 제목과 버튼 배치 확인", author: "테스트 저자",
            isbn13: "9788937460586", coverURL: nil, publisher: "테스트 출판사", publishDate: nil,
            category: nil, bestRank: 1, description: "책소개 펼침 영역입니다.\n하트 상태를 변경해도 펼침 상태는 유지됩니다.",
            itemPage: nil, currentPage: nil
        )
        cell.configure(book: book, displayScale: 1, descriptionWidth: 272,
                       isExpanded: false, isDescriptionLoading: false, wishlistState: state)
        cell.frame = CGRect(x: 0, y: 0, width: 320, height: 140)
        cell.setNeedsLayout()
        cell.layoutIfNeeded()
        let fitted = cell.contentView.systemLayoutSizeFitting(
            CGSize(width: 320, height: 0),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel
        )
        cell.frame.size.height = fitted.height
        cell.setNeedsLayout()
        cell.layoutIfNeeded()
        let heart = try XCTUnwrap(findButton(in: cell, identifier: "wishlistButton"))
        let register = try XCTUnwrap(findButton(in: cell, identifier: "registerBookButton"))
        let heartFrame = heart.convert(heart.bounds, to: cell.contentView)
        let registerFrame = register.convert(register.bounds, to: cell.contentView)
        XCTAssertGreaterThanOrEqual(heartFrame.minY - registerFrame.maxY, 4 - 0.5)
        XCTAssertGreaterThanOrEqual(heart.bounds.width, 44 - 0.01)
        XCTAssertGreaterThanOrEqual(heart.bounds.height, 44 - 0.01)
        XCTAssertLessThanOrEqual(heartFrame.maxX, 320 + 0.01)
        XCTAssertLessThanOrEqual(heartFrame.maxY, cell.contentView.bounds.height + 0.01)
        attachCell(cell, name: "검색 셀 - 기본 하트 - 320pt")

        state.savedISBNs = [book.isbn13]
        cell.configure(book: book, displayScale: 1, descriptionWidth: 272,
                       isExpanded: true, isDescriptionLoading: false, wishlistState: state)
        let expandedSize = cell.contentView.systemLayoutSizeFitting(
            CGSize(width: 320, height: 0),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel
        )
        cell.frame.size.height = expandedSize.height
        cell.setNeedsLayout()
        cell.layoutIfNeeded()
        attachCell(cell, name: "검색 셀 - 저장된 하트와 펼친 책소개 - 320pt")
    }

    private func attachCell(_ cell: BookRowCell, name: String) {
        let image = UIGraphicsImageRenderer(bounds: cell.bounds).image { context in
            cell.layer.render(in: context.cgContext)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func findButton(in view: UIView, identifier: String) -> UIButton? {
        if let button = view as? UIButton, button.accessibilityIdentifier == identifier { return button }
        return view.subviews.compactMap { findButton(in: $0, identifier: identifier) }.first
    }

    func test_repeatedSearchWhileLoading_preservesOriginalRequest() async {
        let h = Harness()
        let first = await requested(h) { h.search("책") }
        let updateCount = h.updates.count
        h.search("책")
        h.search(" \n책\n ")
        await drain()

        XCTAssertEqual(h.repository.requests.count, 1)
        XCTAssertEqual(h.updates.count, updateCount)
        XCTAssertTrue(h.loading)
        XCTAssertFalse(h.loadingMore)
        await finish(first, .success((makeBooks(0..<1), 1)))
        XCTAssertFalse(first.wasCancelled)
        XCTAssertEqual(h.books.map(\.isbn13), ["0"])
        XCTAssertFalse(h.loading)
    }

    func test_repeatedSearchWhileLoadingMore_preservesPageAndAppendsResponse() async {
        let h = Harness()
        let first = await requested(h) { h.search("책") }
        await finish(first, .success((makeBooks(0..<50), 150)))
        let second = await requested(h) { h.next.onNext(()) }
        let updateCount = h.updates.count
        h.search(" 책 ")
        await drain()

        XCTAssertEqual(h.repository.requests.count, 2)
        XCTAssertEqual(h.updates.count, updateCount)
        XCTAssertEqual(h.books.count, 50)
        XCTAssertFalse(h.loading)
        XCTAssertTrue(h.loadingMore)
        await finish(second, .success((makeBooks(50..<100), 150)))
        XCTAssertFalse(second.wasCancelled)
        XCTAssertEqual(h.books.map(\.isbn13), makeBooks(0..<100).map(\.isbn13))
        guard case .append(let start) = h.updates.last?.change else { return XCTFail("append가 필요함") }
        XCTAssertEqual(start, 50)
        let third = await requested(h) { h.next.onNext(()) }
        XCTAssertEqual(third.page, 3)
        await finish(third, .success((makeBooks(100..<150), 150)))
    }

    func test_sameSearchAfterSuccessOrEmptyResult_requestsFirstPageAgain() async {
        let h = Harness()
        let first = await requested(h) { h.search("책") }
        await finish(first, .success((makeBooks(0..<1), 1)))
        let second = await requested(h) { h.search("책") }
        XCTAssertEqual(second.page, 1)
        await finish(second, .success(([], 0)))
        let third = await requested(h) { h.search("책") }
        XCTAssertEqual(third.page, 1)
        await finish(third, .success((makeBooks(1..<2), 1)))
        XCTAssertEqual(h.books.map(\.isbn13), ["1"])
    }

    func test_differentSearchWhileLoading_cancelsOldRequestAndIgnoresOldResponse() async {
        let h = Harness()
        let first = await requested(h) { h.search("첫 번째 책") }
        let second = await requested(h) { h.search("다른 책") }
        await finish(first, .success((makeBooks(0..<1), 1)))
        XCTAssertTrue(first.wasCancelled)
        XCTAssertTrue(h.books.isEmpty)
        XCTAssertTrue(h.loading)
        await finish(second, .success((makeBooks(1..<2), 1)))
        XCTAssertEqual(h.books.map(\.isbn13), ["1"])
        XCTAssertFalse(h.loading)
    }

    func test_repeatedBottomEvents_requestOnePageAndEmitAppend() async {
        let h = Harness()
        let first = await requested(h) { h.search("책") }
        await finish(first, .success((makeBooks(0..<50), 120)))
        let second = await requested(h) { h.next.onNext(()) }
        h.next.onNext(())
        h.next.onNext(())
        XCTAssertEqual(h.repository.requests.count, 2)
        XCTAssertTrue(h.loadingMore)
        await finish(second, .success((makeBooks(50..<100), 120)))
        XCTAssertEqual(h.books.count, 100)
        guard case .append(let start) = h.updates.last?.change else { return XCTFail("append가 필요함") }
        XCTAssertEqual(start, 50)
        let third = await requested(h) { h.next.onNext(()) }
        await finish(third, .success((makeBooks(100..<130), 120)))
        XCTAssertEqual(h.books.count, 120)
        h.next.onNext(())
        await drain()
        XCTAssertEqual(h.repository.requests.map(\.page), [1, 2, 3])
    }

    func test_pageFailure_preservesRowsAndRetriesSamePage() async {
        let h = Harness()
        let first = await requested(h) { h.search("책") }
        await finish(first, .success((makeBooks(0..<50), 150)))
        let second = await requested(h) { h.next.onNext(()) }
        let count = h.updates.count
        await finish(second, .failure(StubError.failed))
        XCTAssertEqual(h.books.count, 50)
        XCTAssertEqual(h.updates.count, count)
        XCTAssertFalse(h.loadingMore)
        XCTAssertEqual(h.errors.count, 1)
        let retry = await requested(h) { h.next.onNext(()) }
        XCTAssertEqual(retry.page, 2)
        await finish(retry, .success((makeBooks(50..<100), 150)))
        XCTAssertEqual(h.books.count, 100)
    }

    func test_searchListSearch_ignoresOldSuccessAndErrorEvenForSameQuery() async {
        let h = Harness()
        let oldSearch = await requested(h) { h.search("같은 책") }
        let oldList = await requested(h) { h.list.onNext(.trending) }
        let current = await requested(h) { h.search("같은 책") }
        await finish(oldSearch, .success((makeBooks(900..<901), 1)))
        await finish(oldList, .failure(StubError.failed))
        XCTAssertTrue(oldSearch.wasCancelled)
        XCTAssertTrue(oldList.wasCancelled)
        XCTAssertTrue(h.loading)
        XCTAssertTrue(h.errors.isEmpty)
        XCTAssertTrue(h.books.isEmpty)
        await finish(current, .success((makeBooks(0..<1), 1)))
        XCTAssertEqual(h.books.map(\.isbn13), ["0"])
        XCTAssertFalse(h.loading)
    }

    func test_reselectingList_ignoresPreviousResponse() async {
        let h = Harness()
        let first = await requested(h) { h.list.onNext(.trending) }
        let replacement = await requested(h) { h.list.onNext(.trending) }
        await finish(first, .success((makeBooks(0..<10), 10)))
        XCTAssertTrue(first.wasCancelled)
        XCTAssertTrue(h.books.isEmpty)
        XCTAssertTrue(h.loading)
        XCTAssertFalse(h.loadingMore)
        await finish(replacement, .success((makeBooks(100..<110), 10)))
        XCTAssertEqual(h.books.first?.isbn13, "100")
        guard case .replace = h.updates.last?.change else { return XCTFail("목록을 교체해야 함") }
    }

    func test_searchResults_stopAtTwoHundredAndFourPages() async {
        let h = Harness()
        var request = await requested(h) { h.search("책") }
        for page in 1...4 {
            await finish(request, .success((makeBooks(((page - 1) * 50)..<(page * 50)), 999)))
            if page < 4 { request = await requested(h) { h.next.onNext(()) } }
        }
        h.next.onNext(())
        await drain()
        XCTAssertEqual(h.books.count, 200)
        XCTAssertEqual(h.repository.requests.map(\.page), [1, 2, 3, 4])
    }

    func test_trending_usesSingleNonPaginatedResponse() async {
        let h = Harness()
        let request = await requested(h) { h.list.onNext(.trending) }
        await finish(request, .success((makeBooks(0..<15), 15)))
        h.next.onNext(())
        await drain()
        XCTAssertEqual(h.books.count, 15)
        XCTAssertEqual(h.repository.requests.map(\.page), [1])
    }

    func test_listEnrichment_displaysBaseListThenReloadsMatchingRowWithFourRequestLimit() async {
        let h = Harness()
        h.repository.holdsMetadataRequests = true
        let listRequest = await requested(h) { h.list.onNext(.popular) }
        await finish(listRequest, .success((makeBooks(0..<50), 50)))

        XCTAssertEqual(h.books.count, 50)
        XCTAssertTrue(h.books.allSatisfy { $0.coverURL == nil && $0.description.isEmpty })
        XCTAssertTrue(h.repository.metadataRequests.isEmpty)
        h.visibleRows.onNext([2, 1, 2, 0, -1, 100])
        await drain()
        XCTAssertEqual(h.repository.metadataRequests.map(\.isbn13), ["0", "1", "2", "3"])
        XCTAssertEqual(h.repository.metadataRequests.count, 4)

        let first = h.repository.metadataRequests[0]
        await finishMetadata(first, .success(metadataBook(isbn13: first.isbn13)))

        XCTAssertEqual(h.repository.metadataRequests.count, 5)
        let row = Int(first.isbn13)!
        XCTAssertEqual(h.books[row].coverURL?.absoluteString, "https://example.com/\(first.isbn13).jpg")
        XCTAssertEqual(h.books[row].description, "보완 설명")
        XCTAssertEqual(h.books[row].title, "책")
        guard case .reload(let rows) = h.updates.last?.change else {
            return XCTFail("보완된 행만 갱신해야 함")
        }
        XCTAssertEqual(rows, [row])
        await finishRemainingMetadata(h, from: 1)
        XCTAssertEqual(h.repository.metadataRequests.map(\.isbn13), (0..<8).map { String($0) })
        h.visibleRows.onNext([0, 1, 2])
        await drain()
        XCTAssertEqual(h.repository.metadataRequests.count, 8)
    }

    func test_listEnrichment_failureContinuesWithNextISBN() async {
        let h = Harness()
        h.repository.holdsMetadataRequests = true
        let listRequest = await requested(h) { h.list.onNext(.trending) }
        await finish(listRequest, .success((makeBooks(0..<5), 5)))
        h.visibleRows.onNext([0])
        await drain()
        XCTAssertEqual(h.repository.metadataRequests.count, 4)

        await finishMetadata(h.repository.metadataRequests[0], .failure(StubError.failed))

        XCTAssertEqual(h.repository.metadataRequests.count, 5)
        XCTAssertTrue(h.errors.isEmpty)
        XCTAssertEqual(h.books.count, 5)
        await finishRemainingMetadata(h, from: 1)
        h.visibleRows.onNext([0, 1, 2, 3, 4])
        await drain()
        XCTAssertEqual(h.repository.metadataRequests.count, 5)
    }

    func test_listEnrichment_ignoresResultAfterModeChanges() async {
        let h = Harness()
        h.repository.holdsMetadataRequests = true
        let listRequest = await requested(h) { h.list.onNext(.popular) }
        await finish(listRequest, .success((makeBooks(0..<1), 1)))
        h.visibleRows.onNext([0])
        await drain()
        let oldMetadata = h.repository.metadataRequests[0]

        let searchRequest = await requested(h) { h.search("다른 책") }
        await finish(searchRequest, .success((makeBooks(100..<101), 1)))
        h.visibleRows.onNext([0])
        await drain()
        await finishMetadata(oldMetadata, .success(metadataBook(isbn13: "0")))

        XCTAssertEqual(h.books.map(\.isbn13), ["100"])
        XCTAssertNil(h.books.first?.coverURL)
        XCTAssertEqual(h.repository.metadataRequests.count, 1)
    }

    func test_listEnrichment_scrollReplacesPendingRowsAndPrioritizesVisibleRows() async {
        let h = Harness()
        h.repository.holdsMetadataRequests = true
        let request = await requested(h) { h.list.onNext(.popular) }
        await finish(request, .success((makeBooks(0..<50), 50)))
        h.visibleRows.onNext([0])
        await drain()
        h.visibleRows.onNext([20, 21])
        h.visibleRows.onNext([30, 31])
        await drain()
        XCTAssertEqual(h.repository.metadataRequests.count, 4)

        await finishRemainingMetadata(h)
        XCTAssertEqual(h.repository.metadataRequests.map(\.isbn13),
                       ["0", "1", "2", "3"] + (30..<37).map { String($0) })
    }

    func test_listEnrichment_emptyWindowStopsQueueAndReappearanceResumesUnattemptedRows() async {
        let h = Harness()
        h.repository.holdsMetadataRequests = true
        let request = await requested(h) { h.list.onNext(.trending) }
        await finish(request, .success((makeBooks(0..<10), 10)))
        h.visibleRows.onNext([0])
        await drain()
        h.visibleRows.onNext([])
        await finishRemainingMetadata(h)
        XCTAssertEqual(h.repository.metadataRequests.count, 4)

        h.visibleRows.onNext([0])
        await drain()
        await finishRemainingMetadata(h, from: 4)
        XCTAssertEqual(h.repository.metadataRequests.map(\.isbn13), (0..<6).map { String($0) })
    }

    func test_listEnrichment_duplicateISBNsAndMissingResults_areAttemptedOncePerList() async {
        let h = Harness()
        h.repository.holdsMetadataRequests = true
        let request = await requested(h) { h.list.onNext(.popular) }
        let books = makeBooks(0..<1) + makeBooks(0..<1) + makeBooks(1..<2)
        await finish(request, .success((books, books.count)))
        h.visibleRows.onNext([0, 1, 2])
        await drain()
        XCTAssertEqual(h.repository.metadataRequests.map(\.isbn13), ["0", "1"])
        await finishRemainingMetadata(h)
        h.visibleRows.onNext([0, 1, 2])
        await drain()
        XCTAssertEqual(h.repository.metadataRequests.count, 2)
        XCTAssertTrue(h.errors.isEmpty)

        let reload = await requested(h) { h.list.onNext(.popular) }
        h.visibleRows.onNext([0])
        await drain()
        XCTAssertEqual(h.repository.metadataRequests.count, 2)
        await finish(reload, .success((books, books.count)))
        h.visibleRows.onNext([0])
        await drain()
        XCTAssertEqual(h.repository.metadataRequests.count, 4)
        await finishRemainingMetadata(h, from: 2)
    }

    func test_listEnrichment_invalidRowsAndEmptyList_doNotRequestMetadata() async {
        let h = Harness()
        h.repository.holdsMetadataRequests = true
        let request = await requested(h) { h.list.onNext(.popular) }
        await finish(request, .success((makeBooks(0..<2), 2)))
        h.visibleRows.onNext([-1, 2, Int.max])
        await drain()
        XCTAssertTrue(h.repository.metadataRequests.isEmpty)
        let empty = await requested(h) { h.list.onNext(.trending) }
        await finish(empty, .success(([], 0)))
        h.visibleRows.onNext([0])
        await drain()
        XCTAssertTrue(h.repository.metadataRequests.isEmpty)
    }

    func test_emptyNextPage_finishesWithoutReloadingExistingRows() async {
        let h = Harness()
        let first = await requested(h) { h.search("책") }
        await finish(first, .success((makeBooks(0..<50), 200)))
        let second = await requested(h) { h.next.onNext(()) }
        let count = h.updates.count
        await finish(second, .success(([], 200)))
        h.next.onNext(())
        await drain()
        XCTAssertEqual(h.updates.count, count)
        XCTAssertEqual(h.books.count, 50)
        XCTAssertEqual(h.repository.requests.count, 2)
        XCTAssertFalse(h.loadingMore)
    }

    func test_shortNextPage_stopsPagination() async {
        let h = Harness()
        let first = await requested(h) { h.search("책") }
        await finish(first, .success((makeBooks(0..<50), 200)))
        let second = await requested(h) { h.next.onNext(()) }
        await finish(second, .success((makeBooks(50..<53), 200)))
        h.next.onNext(())
        await drain()
        XCTAssertEqual(h.books.count, 53)
        XCTAssertEqual(h.repository.requests.count, 2)
    }

    func test_shortMappedPage_continuesWhenKakaoReportsMoreResults() async {
        let h = Harness()
        let first = await requested(h) { h.search("책") }
        await finish(first, .success((makeBooks(0..<50), 200)))
        let second = await requested(h) { h.next.onNext(()) }
        await finish(second, .success((makeBooks(50..<99), 200)), isEnd: false)

        let third = await requested(h) { h.next.onNext(()) }
        XCTAssertEqual(third.page, 3)
        await finish(third, .success((makeBooks(99..<100), 200)), isEnd: true)

        h.next.onNext(())
        await drain()
        XCTAssertEqual(h.books.count, 100)
        XCTAssertEqual(h.repository.requests.map(\.page), [1, 2, 3])
    }

    func test_firstPageFailure_clearsPreviousListAndCanSearchAgain() async {
        let h = Harness()
        let first = await requested(h) { h.list.onNext(.popular) }
        await finish(first, .success((makeBooks(0..<50), 50)))
        h.next.onNext(())
        await drain()
        XCTAssertEqual(h.repository.requests.count, 1)
        let failed = await requested(h) { h.search("다른 책") }
        await finish(failed, .failure(StubError.failed))
        XCTAssertTrue(h.books.isEmpty)
        XCTAssertFalse(h.loading)
        XCTAssertEqual(h.errors.count, 1)
        let retry = await requested(h) { h.search("다른 책") }
        await finish(retry, .success(([], 0)))
        h.next.onNext(())
        await drain()
        XCTAssertEqual(h.repository.requests.count, 3)
    }

    func test_registration_ignoresRepeatedTapWhileDetailLookupIsPending() async {
        let h = Harness()
        h.repository.holdsRegistrations = true
        let started = expectation(description: "등록 시작")
        h.repository.onRegistrationRequested = { started.fulfill() }
        let books = makeBooks(0..<2)

        h.register.onNext(books[0])
        await fulfillment(of: [started], timeout: 2)
        h.register.onNext(books[1])
        await drain()

        XCTAssertEqual(h.repository.registrations.map(\.book.isbn13), ["0"])
        XCTAssertEqual(h.registrationCompletedCount, 0)

        let completed = expectation(description: "등록 완료 이벤트")
        h.onRegistrationCompleted = { completed.fulfill() }
        h.repository.registrations[0].continuation.resume()
        await fulfillment(of: [completed], timeout: 2)
        XCTAssertEqual(h.registrationCompletedCount, 1)
    }

    func test_descriptionExpansion_replacesKakaoDescriptionWithBookSupplement() async {
        let h = Harness()
        let listRequest = await requested(h) { h.search("책") }
        await finish(listRequest, .success((makeBooks(0..<1), 1)))
        h.repository.supplement = BookDetailMetadata(
            isbn13: "0", title: "", author: "", publisher: "", publishDate: nil,
            coverURL: nil, description: "정보나루 상세 책소개"
        )
        let requested = expectation(description: "상세 설명 요청")
        h.repository.onSupplementRequested = { requested.fulfill() }

        h.description.onNext(h.books[0])
        await fulfillment(of: [requested], timeout: 2)
        await drain()
        await drain()

        XCTAssertEqual(h.books[0].description, "정보나루 상세 책소개")
        XCTAssertEqual(h.descriptionReadyISBNs, ["0"])
        guard case .reload(let rows) = h.updates.last?.change else {
            return XCTFail("설명이 변경된 행을 갱신해야 함")
        }
        XCTAssertEqual(rows, [0])
    }

    func test_descriptionExpansion_emitsReadyWithKakaoFallbackWhenSupplementFails() async {
        let h = Harness()
        let kakaoBook = Book(
            title: "책", author: "저자", isbn13: "fallback", coverURL: nil,
            publisher: "출판사", publishDate: nil, category: nil, bestRank: nil,
            description: "카카오 책소개", itemPage: nil, currentPage: nil
        )
        let listRequest = await requested(h) { h.search("책") }
        await finish(listRequest, .success(([kakaoBook], 1)))
        h.repository.supplementError = StubError.failed
        let requested = expectation(description: "상세 설명 요청")
        h.repository.onSupplementRequested = { requested.fulfill() }

        h.description.onNext(kakaoBook)
        await fulfillment(of: [requested], timeout: 2)
        await drain()
        await drain()

        XCTAssertEqual(h.books[0].description, "카카오 책소개")
        XCTAssertEqual(h.descriptionReadyISBNs, ["fallback"])
    }

    private func requested(_ h: Harness, action: () -> Void) async -> PendingRequest {
        let started = expectation(description: "요청 시작")
        h.repository.onRequested = { started.fulfill() }
        action()
        await fulfillment(of: [started], timeout: 2)
        h.repository.onRequested = nil
        return h.repository.requests.last!
    }

    private func finish(
        _ request: PendingRequest,
        _ result: Result<([Book], Int), Error>,
        isEnd: Bool? = nil
    ) async {
        let returned = expectation(description: "응답 반환")
        request.onReturned = { returned.fulfill() }
        request.continuation.resume(with: result.map { books, totalResults in
            BookSearchPage(
                books: books,
                totalResults: totalResults,
                isEnd: isEnd ?? (books.isEmpty || books.count < 50 || books.count >= totalResults)
            )
        })
        await fulfillment(of: [returned], timeout: 2)
        await drain()
    }

    private func drain() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private func finishMetadata(
        _ request: PendingMetadataRequest,
        _ result: Result<BookListMetadata?, Error>
    ) async {
        request.continuation.resume(with: result)
        await drain()
        await drain()
    }

    private func finishRemainingMetadata(_ h: Harness, from start: Int = 0) async {
        var index = start
        while index < h.repository.metadataRequests.count {
            await finishMetadata(h.repository.metadataRequests[index], .success(nil))
            index += 1
        }
    }

    private func metadataBook(isbn13: String) -> BookListMetadata {
        BookListMetadata(
            isbn13: isbn13,
            coverURL: URL(string: "https://example.com/\(isbn13).jpg"),
            description: "보완 설명"
        )
    }

    private func makeBooks(_ range: Range<Int>) -> [Book] {
        range.map { index in
            Book(title: "책", author: "저자", isbn13: "\(index)", coverURL: nil,
                 publisher: "출판사", publishDate: nil, category: nil, bestRank: nil,
                 description: "", itemPage: nil, currentPage: nil)
        }
    }
}

private enum StubError: Error { case failed }

@MainActor
private func wishlistItem(isbn13: String) -> WishlistItem {
    WishlistItem(isbn13: isbn13, title: "책", author: "저자", publisher: "출판사",
                 coverURL: nil, description: "책소개", addedAt: Date(timeIntervalSince1970: 100))
}

@MainActor
private final class ControlledWishlistRepository: WishlistRepositoryProtocol {
    var savedISBNs: Set<String> = []
    var addedBooks: [Book] = []
    var deletedISBNs: [String] = []
    var fetchCount = 0
    var fetchError: Error?
    var mutationError: Error?
    var holdsMutations = false
    var holdsFetches = false
    var fetches: [CheckedContinuation<[WishlistItem], Error>] = []
    var mutations: [CheckedContinuation<Void, Error>] = []

    func addBook(_ book: Book) async throws {
        addedBooks.append(book)
        try await mutate()
        savedISBNs.insert(book.isbn13.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func deleteBook(isbn13: String) async throws {
        deletedISBNs.append(isbn13)
        try await mutate()
        savedISBNs.remove(isbn13)
    }

    func containsBook(isbn13: String) async throws -> Bool { savedISBNs.contains(isbn13) }

    func fetchAllItems() async throws -> [WishlistItem] {
        fetchCount += 1
        if let fetchError { throw fetchError }
        if holdsFetches {
            return try await withCheckedThrowingContinuation { fetches.append($0) }
        }
        return savedISBNs.map { wishlistItem(isbn13: $0) }
    }

    private func mutate() async throws {
        if let mutationError { throw mutationError }
        if holdsMutations {
            try await withCheckedThrowingContinuation { mutations.append($0) }
        }
    }
}

@MainActor
private final class Harness {
    let repository = ControlledRepository()
    let wishlistRepository = ControlledWishlistRepository()
    let appeared = PublishSubject<Void>()
    let wishlistTap = PublishSubject<Book>()
    var wishlistState = BookSearchViewModel.WishlistState()
    var wishlistMessages: [String] = []
    var registeredISBNs: Set<String> = []
    let query = PublishSubject<String>()
    let trigger = PublishSubject<Void>()
    let list = PublishSubject<BookSearchViewModel.BookListType>()
    let next = PublishSubject<Void>()
    let visibleRows = PublishSubject<[Int]>()
    let description = PublishSubject<Book>()
    let register = PublishSubject<Book>()
    let bag = DisposeBag()
    let viewModel: BookSearchViewModel
    var updates: [BookSearchViewModel.ListUpdate] = []
    var errors: [String] = []
    var loading = false
    var loadingMore = false
    var registrationCompletedCount = 0
    var onRegistrationCompleted: (() -> Void)?
    var descriptionReadyISBNs: [String] = []
    var books: [Book] { updates.last?.books ?? [] }

    init(savedBooks: [Book] = []) {
        repository.savedBooks.accept(savedBooks)
        viewModel = BookSearchViewModel(repository: repository, wishlistRepository: wishlistRepository)
        let output = viewModel.transform(input: .init(
            viewDidLoad: .never(), listSelection: list, searchQuery: query,
            searchTrigger: trigger, loadNextPage: next,
            visibleRows: visibleRows,
            descriptionBook: description, registerBook: register,
            screenAppeared: appeared, toggleWishlist: wishlistTap
        ))
        output.wishlistState.drive(onNext: { [weak self] in self?.wishlistState = $0 }).disposed(by: bag)
        output.registeredISBNs.drive(onNext: { [weak self] in self?.registeredISBNs = $0 }).disposed(by: bag)
        output.wishlistMessage.emit(onNext: { [weak self] in self?.wishlistMessages.append($0) }).disposed(by: bag)
        output.listUpdates.drive(onNext: { [weak self] in self?.updates.append($0) }).disposed(by: bag)
        output.isLoading.drive(onNext: { [weak self] in self?.loading = $0 }).disposed(by: bag)
        output.isLoadingMore.drive(onNext: { [weak self] in self?.loadingMore = $0 }).disposed(by: bag)
        output.errorMessage.emit(onNext: { [weak self] in self?.errors.append($0) }).disposed(by: bag)
        output.descriptionReady.emit(onNext: { [weak self] in
            self?.descriptionReadyISBNs.append($0)
        }).disposed(by: bag)
        output.registerCompleted.emit(onNext: { [weak self] in
            self?.registrationCompletedCount += 1
            self?.onRegistrationCompleted?()
        }).disposed(by: bag)
    }

    func search(_ text: String) {
        query.onNext(text)
        trigger.onNext(())
    }
}

@MainActor
private final class PendingRequest {
    let page: Int
    let continuation: CheckedContinuation<BookSearchPage, Error>
    var wasCancelled = false
    var onReturned: (() -> Void)?

    init(page: Int, continuation: CheckedContinuation<BookSearchPage, Error>) {
        self.page = page
        self.continuation = continuation
    }
}

@MainActor
private final class PendingMetadataRequest {
    let isbn13: String
    let continuation: CheckedContinuation<BookListMetadata?, Error>

    init(isbn13: String, continuation: CheckedContinuation<BookListMetadata?, Error>) {
        self.isbn13 = isbn13
        self.continuation = continuation
    }
}

@MainActor
private final class PendingRegistration {
    let book: Book
    let continuation: CheckedContinuation<Void, Error>

    init(book: Book, continuation: CheckedContinuation<Void, Error>) {
        self.book = book
        self.continuation = continuation
    }
}

/// 의도적으로 취소를 무시하고 응답해 ViewModel의 세대 교체를 검증한다.
@MainActor
private final class ControlledRepository: BookRepositoryProtocol {
    let savedBooks = BehaviorRelay<[Book]>(value: [])
    var requests: [PendingRequest] = []
    var metadataRequests: [PendingMetadataRequest] = []
    var registrations: [PendingRegistration] = []
    var onRequested: (() -> Void)?
    var onRegistrationRequested: (() -> Void)?
    var onSupplementRequested: (() -> Void)?
    var holdsMetadataRequests = false
    var holdsRegistrations = false
    var supplement: BookDetailMetadata?
    var supplementError: Error?

    private func fetch(page: Int) async throws -> BookSearchPage {
        var pending: PendingRequest?
        defer {
            pending?.wasCancelled = Task.isCancelled
            pending?.onReturned?()
        }
        return try await withCheckedThrowingContinuation { continuation in
            let request = PendingRequest(page: page, continuation: continuation)
            pending = request
            requests.append(request)
            onRequested?()
        }
    }

    func fetchPopularBooks() async throws -> [Book] { try await fetch(page: 1).books }
    func fetchTrendingBooks() async throws -> [Book] { try await fetch(page: 1).books }
    func searchBooks(query: String, page: Int) async throws -> BookSearchPage {
        try await fetch(page: page)
    }
    func fetchListBookMetadata(isbn13: String) async throws -> BookListMetadata? {
        guard holdsMetadataRequests else { return nil }
        return try await withCheckedThrowingContinuation { continuation in
            metadataRequests.append(PendingMetadataRequest(
                isbn13: isbn13,
                continuation: continuation
            ))
        }
    }
    func fetchBookSupplement(isbn13: String) async throws -> BookDetailMetadata? {
        onSupplementRequested?()
        if let supplementError { throw supplementError }
        return supplement
    }
    func fetchSavedBooks() -> Observable<[Book]> { savedBooks.asObservable() }
    func registerSearchedBook(_ book: Book) async throws {
        guard holdsRegistrations else { return }
        try await withCheckedThrowingContinuation { continuation in
            registrations.append(PendingRegistration(book: book, continuation: continuation))
            onRegistrationRequested?()
        }
    }
    func saveBook(_ book: Book) async throws { }
    func deleteBook(_ book: Book) async throws { }
    func deleteAllBooks() async throws { }
    func updateReadingProgress(isbn13: String, itemPage: Int, currentPage: Int) async throws { }
    func reorderBooks(orderedISBNs: [String]) async throws { }
}

// Keep search-specific setup in the test harness, outside the shared cell.
@MainActor
private extension BookRowCell {
    func configure(
        book: Book, displayScale: CGFloat, descriptionWidth: CGFloat,
        isExpanded: Bool, isDescriptionLoading: Bool,
        wishlistState: BookSearchViewModel.WishlistState, registeredISBNs: Set<String> = []
    ) {
        let content = BookRowContent(book: book)
        configure(content: content, displayScale: displayScale, descriptionWidth: descriptionWidth,
                  isExpanded: isExpanded, isDescriptionLoading: isDescriptionLoading,
                  primaryAction: .registration(isRegistered: registeredISBNs.contains(content.isbn13)),
                  wishlistAction: .wishlist(isSaved: wishlistState.savedISBNs.contains(content.isbn13),
                      isEnabled: wishlistState.isLoaded && !wishlistState.isRefreshing,
                      isPending: wishlistState.pendingISBNs.contains(content.isbn13)))
    }

    func setRegistrationState(_ isbns: Set<String>) {
        setPrimaryAction(.registration(isRegistered: isbn13.map { isbns.contains($0) } ?? false))
    }

    func setWishlistState(_ state: BookSearchViewModel.WishlistState) {
        setWishlistAction(.wishlist(isSaved: isbn13.map { state.savedISBNs.contains($0) } ?? false,
            isEnabled: state.isLoaded && !state.isRefreshing,
            isPending: isbn13.map { state.pendingISBNs.contains($0) } ?? false))
    }
}
