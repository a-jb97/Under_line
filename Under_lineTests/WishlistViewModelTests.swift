import XCTest
import UIKit
import RxSwift
import RxCocoa
@testable import Under_line

@MainActor
final class WishlistViewModelTests: XCTestCase {
    func test_search_filtersTitleAndAuthorImmediatelyWithoutFetchingAgain() async {
        let h = WishlistHarness()
        await load(h)
        let all = h.state.items
        for (query, expected) in [("  Swift \n", ["a", "c"]), ("한강", ["b"]), ("SWIFT", ["a", "c"])] {
            h.query.accept(query)
            XCTAssertEqual(h.state.items.map(\.isbn13), expected)
        }
        h.query.accept(" \n ")
        XCTAssertEqual(h.state.items, all)
        XCTAssertEqual(h.repository.fetchCount, 1)
    }

    func test_search_distinguishesEmptyWishlistFromNoMatchingResults() async {
        let h = WishlistHarness()
        await load(h)
        h.query.accept("없는 제목")
        XCTAssertEqual(h.state.emptyMessage, "검색 결과가 없습니다")
        h.repository.items = []
        h.appeared.accept(())
        await drain()
        XCTAssertEqual(h.state.emptyMessage, "위시리스트에 담은 도서가 없습니다")
        XCTAssertEqual(h.state.query, "없는 제목")
    }

    func test_search_duringLoadingUsesLatestQueryWhenResponseArrives() async {
        let h = WishlistHarness()
        h.repository.holdsFetches = true
        h.appeared.accept(())
        await drain()
        h.query.accept("한강")
        h.repository.fetches[0].resume(returning: h.repository.items)
        await drain()
        XCTAssertEqual(h.state.items.map(\.isbn13), ["b"])
    }

    func test_delete_filteredResultRemovesOnlyMatchingOriginalItemAfterSuccess() async {
        let h = WishlistHarness()
        await load(h)
        h.query.accept("한강")
        h.repository.holdsDeletes = true
        h.delete.accept("b")
        XCTAssertEqual(h.state.items.map(\.isbn13), ["b"])
        XCTAssertEqual(h.state.deletingISBNs, ["b"])
        await drain()
        h.repository.deletions[0].resume()
        await drain()
        XCTAssertTrue(h.state.items.isEmpty)
        XCTAssertEqual(h.state.emptyMessage, "검색 결과가 없습니다")
        h.query.accept("")
        XCTAssertEqual(h.state.items.map(\.isbn13), ["a", "c"])
        XCTAssertEqual(h.messages.last, "위시리스트에서 삭제했습니다.")
    }

    func test_delete_failureKeepsItemAndCanRetry() async {
        let h = WishlistHarness()
        await load(h)
        h.repository.deleteError = WishlistTestError.failed
        h.delete.accept("b")
        await drain()
        XCTAssertEqual(h.state.items.count, 3)
        XCTAssertTrue(h.state.deletingISBNs.isEmpty)
        XCTAssertEqual(h.messages.count, 1)
        h.repository.deleteError = nil
        h.delete.accept("b")
        await drain()
        XCTAssertEqual(h.state.items.map(\.isbn13), ["a", "c"])
    }

    func test_delete_repeatedTapIsBlockedButDifferentISBNsCanProceed() async {
        let h = WishlistHarness()
        await load(h)
        h.repository.holdsDeletes = true
        h.delete.accept("a")
        h.delete.accept("a")
        h.delete.accept("b")
        await drain()
        XCTAssertEqual(h.repository.deletedISBNs, ["a", "b"])
        for continuation in h.repository.deletions { continuation.resume() }
        await drain()
        XCTAssertEqual(h.state.items.map(\.isbn13), ["c"])
        XCTAssertTrue(h.state.deletingISBNs.isEmpty)
    }

    func test_reload_afterDeletionIsDeferredAndDoesNotRestoreRemovedItem() async {
        let h = WishlistHarness()
        await load(h)
        h.repository.holdsDeletes = true
        h.delete.accept("a")
        await drain()
        h.appeared.accept(())
        XCTAssertEqual(h.repository.fetchCount, 1)
        h.repository.deletions[0].resume()
        await drain()
        await drain()
        XCTAssertEqual(h.repository.fetchCount, 2)
        XCTAssertEqual(h.state.items.map(\.isbn13), ["b", "c"])
    }

    func test_reload_lateCancelledSnapshotCannotReplaceLatestList() async {
        let h = WishlistHarness()
        h.repository.holdsFetches = true
        h.appeared.accept(())
        await drain()
        h.appeared.accept(())
        await drain()
        h.repository.fetches[1].resume(returning: [h.repository.items[1]])
        await drain()
        h.repository.fetches[0].resume(returning: h.repository.items)
        await drain()
        XCTAssertEqual(h.state.items.map(\.isbn13), ["b"])
    }

    func test_reload_failureShowsRetryStateAndRetryKeepsSearchQuery() async {
        let h = WishlistHarness()
        h.repository.fetchError = WishlistTestError.failed
        h.query.accept("한강")
        await load(h)
        XCTAssertNotNil(h.state.loadError)
        XCTAssertNil(h.state.emptyMessage)
        XCTAssertFalse(h.state.isLoading)
        h.delete.accept("b")
        await drain()
        XCTAssertTrue(h.repository.deletedISBNs.isEmpty)
        h.repository.fetchError = nil
        h.retry.accept(())
        await drain()
        XCTAssertNil(h.state.loadError)
        XCTAssertEqual(h.state.items.map(\.isbn13), ["b"])
    }

    func test_delete_lastItemShowsEmptyWishlistMessage() async {
        let h = WishlistHarness()
        h.repository.items = [h.repository.items[0]]
        await load(h)
        h.delete.accept("a")
        await drain()
        XCTAssertEqual(h.state.emptyMessage, "위시리스트에 담은 도서가 없습니다")
    }

    func test_sharedCell_purchaseEnabledAndReuseRestoresRegistrationAction() throws {
        let item = wishlistFixtures()[0]
        let cell = BookRowCell(style: .default, reuseIdentifier: BookRowCell.reuseID)
        cell.configure(content: BookRowContent(item: item), displayScale: 1, descriptionWidth: 272,
                       isExpanded: true, isDescriptionLoading: false, primaryAction: .purchase,
                       wishlistAction: .wishlist(isSaved: true, isEnabled: true))
        let purchase = try XCTUnwrap(findView(cell, id: "purchaseBookButton") as? UIButton)
        let heart = try XCTUnwrap(findView(cell, id: "wishlistButton") as? UIButton)
        XCTAssertTrue(purchase.isEnabled)
        XCTAssertEqual(purchase.accessibilityLabel, "도서 구매")
        XCTAssertTrue(heart.isSelected)
        XCTAssertTrue(heart.isEnabled)
        var deleted: [String] = []
        cell.onToggleWishlist = { deleted.append($0) }
        heart.sendActions(for: .touchUpInside)
        XCTAssertEqual(deleted, [item.isbn13])
        cell.prepareForReuse()
        XCTAssertFalse(heart.isEnabled)
        XCTAssertNil(cell.onToggleWishlist)
        cell.configure(content: BookRowContent(item: item), displayScale: 1, descriptionWidth: 272,
                       isExpanded: false, isDescriptionLoading: false,
                       primaryAction: .registration(isRegistered: false),
                       wishlistAction: .wishlist(isSaved: false, isEnabled: true))
        XCTAssertNotNil(findView(cell, id: "registerBookButton"))
        XCTAssertTrue(purchase.isEnabled)
        XCTAssertFalse(heart.isSelected)
    }

    func test_sharedCell_shadowTracksCardLayoutWithoutAnotherCellLayoutOrTap() throws {
        let cell = BookRowCell(style: .default, reuseIdentifier: BookRowCell.reuseID)
        cell.configure(content: BookRowContent(item: wishlistFixtures()[0]), displayScale: 1,
                       descriptionWidth: 272, isExpanded: false, isDescriptionLoading: false,
                       primaryAction: .purchase, wishlistAction: .wishlist(isSaved: true, isEnabled: true))
        cell.frame = CGRect(x: 0, y: 0, width: 320, height: 120)
        cell.setNeedsLayout()
        cell.layoutIfNeeded()
        let card = try XCTUnwrap(cell.contentView.subviews.first { $0.layer.shadowOpacity > 0 })

        // Auto Layout can finalize a descendant's bounds after its cell has laid out.
        // Updating only the card must update its shadow on that same layout pass.
        for size in [CGSize(width: 288, height: 108), CGSize(width: 350, height: 180)] {
            card.bounds = CGRect(origin: .zero, size: size)
            card.setNeedsLayout()
            card.layoutIfNeeded()
            let path = try XCTUnwrap(card.layer.shadowPath)
            XCTAssertEqual(path.boundingBoxOfPath.width, size.width, accuracy: 0.01)
            XCTAssertEqual(path.boundingBoxOfPath.height, size.height, accuracy: 0.01)
        }
    }

    func test_screen_liveSearchExpansionAndDeletionUseStableISBNs() async throws {
        let repository = WishlistStubRepository()
        let screen = WishlistViewController(repository: repository)
        let root = UIViewController()
        let navigation = UINavigationController(rootViewController: root)
        navigation.setNavigationBarHidden(true, animated: false)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        defer { window.isHidden = true }
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        navigation.pushViewController(screen, animated: false)
        screen.loadViewIfNeeded()
        screen.viewWillAppear(false)
        await drain()
        screen.view.layoutIfNeeded()
        let table = try XCTUnwrap(findView(screen.view, id: "wishlistTable") as? UITableView)
        let field = try XCTUnwrap(findView(screen.view, id: "bookSearchField") as? UITextField)
        XCTAssertEqual(table.numberOfRows(inSection: 0), 3)
        for cell in table.visibleCells {
            let card = try XCTUnwrap(cell.contentView.subviews.first { $0.layer.shadowOpacity > 0 })
            let shadow = try XCTUnwrap(card.layer.shadowPath)
            XCTAssertGreaterThan(card.bounds.width, 0)
            XCTAssertGreaterThan(card.bounds.height, 0)
            XCTAssertEqual(shadow.boundingBoxOfPath.width, card.bounds.width, accuracy: 0.01)
            XCTAssertEqual(shadow.boundingBoxOfPath.height, card.bounds.height, accuracy: 0.01)
        }
        attach(screen.view, name: "위시리스트 - 전체 목록")

        field.text = "한강"
        field.sendActions(for: .editingChanged)
        screen.view.layoutIfNeeded()
        XCTAssertEqual(table.numberOfRows(inSection: 0), 1)
        let indexPath = IndexPath(row: 0, section: 0)
        let collapsedHeight = table.rectForRow(at: indexPath).height
        table.delegate?.tableView?(table, didSelectRowAt: indexPath)
        table.layoutIfNeeded()
        XCTAssertGreaterThan(table.rectForRow(at: indexPath).height, collapsedHeight)
        attach(screen.view, name: "위시리스트 - 실시간 검색과 책소개 펼침")
        let cell = try XCTUnwrap(table.cellForRow(at: indexPath) as? BookRowCell)
        let heart = try XCTUnwrap(findView(cell, id: "wishlistButton") as? UIButton)
        heart.sendActions(for: .touchUpInside)
        await drain()
        XCTAssertEqual(repository.deletedISBNs, ["b"])
        XCTAssertEqual(table.numberOfRows(inSection: 0), 0)
        let status = try XCTUnwrap(findView(screen.view, id: "wishlistStatusLabel") as? UILabel)
        XCTAssertEqual(status.text, "검색 결과가 없습니다")
        field.text = ""
        field.sendActions(for: .editingChanged)
        screen.view.layoutIfNeeded()
        XCTAssertEqual(table.numberOfRows(inSection: 0), 2)
        let back = try XCTUnwrap(findView(screen.view, id: "wishlistBackButton") as? UIButton)
        back.sendActions(for: .touchUpInside)
        XCTAssertTrue(navigation.topViewController === root)
    }

    func test_purchase_emitsDestinationAndInvalidISBNMessage() async {
        let service = try! BookPurchaseService(resolvers: [.yes24: YES24PurchaseResolver()])
        let model = WishlistViewModel(repository: WishlistStubRepository(), purchaseService: service)
        let requests = PublishRelay<WishlistViewModel.PurchaseRequest>()
        let bag = DisposeBag()
        let output = model.transform(input: .init(screenAppeared: .empty(), retry: .empty(),
            searchQuery: .empty(), deleteISBN: .empty(), purchase: requests.asObservable()))
        var destinations: [BookPurchaseDestination] = []
        var messages: [String] = []
        output.destination.emit(onNext: { destinations.append($0) }).disposed(by: bag)
        output.message.emit(onNext: { messages.append($0) }).disposed(by: bag)
        requests.accept(.init(isbn13: "9780132350884", store: .yes24))
        requests.accept(.init(isbn13: "9780132350884", store: .yes24))
        await drain()
        XCTAssertEqual(destinations.count, 1)
        requests.accept(.init(isbn13: "invalid", store: .yes24))
        await drain()
        XCTAssertEqual(messages, ["올바른 ISBN13이 아닙니다."])
    }

    func test_purchaseTap_readsLatestPreferenceAndDoesNotPersistOneTimeSelection() async throws {
        let name = "wishlist-preference-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = BookPurchasePreferenceStore(defaults: defaults)
        let service = try BookPurchaseService(resolvers: [.yes24: YES24PurchaseResolver()])
        let model = WishlistViewModel(repository: WishlistStubRepository(), purchaseService: service, preferences: preferences)
        let tap = PublishRelay<String>()
        let selected = PublishRelay<WishlistViewModel.PurchaseRequest>()
        let output = model.transform(input: .init(screenAppeared: .empty(), retry: .empty(), searchQuery: .empty(), deleteISBN: .empty(), purchaseTap: tap.asObservable(), purchase: selected.asObservable()))
        let bag = DisposeBag()
        var menus: [String] = []
        var destinations: [BookPurchaseDestination] = []
        output.selectStore.emit(onNext: { menus.append($0) }).disposed(by: bag)
        output.destination.emit(onNext: { destinations.append($0) }).disposed(by: bag)
        tap.accept("9780132350884")
        XCTAssertEqual(menus, ["9780132350884"])
        selected.accept(.init(isbn13: "9780132350884", store: .yes24))
        await drain()
        XCTAssertEqual(preferences.current, .askEveryTime)
        preferences.save(.store(.yes24))
        tap.accept("9780132350884")
        await drain()
        XCTAssertEqual(menus.count, 1)
        XCTAssertEqual(destinations.count, 2)
        preferences.save(.askEveryTime)
        tap.accept("9780132350884")
        XCTAssertEqual(menus.count, 2)
    }

    private func load(_ harness: WishlistHarness) async {
        harness.appeared.accept(())
        await drain()
    }

    private func drain() async {
        for _ in 0..<3 {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }

    private func findView(_ view: UIView, id: String) -> UIView? {
        if view.accessibilityIdentifier == id { return view }
        return view.subviews.compactMap { findView($0, id: id) }.first
    }

    private func attach(_ view: UIView, name: String) {
        let image = UIGraphicsImageRenderer(bounds: view.bounds).image { context in
            view.layer.render(in: context.cgContext)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private enum WishlistTestError: Error { case failed }

@MainActor
private func wishlistFixtures() -> [WishlistItem] {
    [
        WishlistItem(isbn13: "a", title: "Swift 프로그래밍", author: "개발자", publisher: "출판사",
                     coverURL: nil, description: "Swift 언어를 공부합니다.", addedAt: Date(timeIntervalSince1970: 300)),
        WishlistItem(isbn13: "b", title: "소년이 온다", author: "한강", publisher: "창비",
                     coverURL: nil, description: "책소개 첫 번째 줄입니다.\n두 번째 줄입니다.\n세 번째 줄입니다.", addedAt: Date(timeIntervalSince1970: 200)),
        WishlistItem(isbn13: "c", title: "개발 이야기", author: "Swift 저자", publisher: "출판사",
                     coverURL: nil, description: "", addedAt: Date(timeIntervalSince1970: 100))
    ]
}

@MainActor
private final class WishlistHarness {
    let repository = WishlistStubRepository()
    let appeared = PublishRelay<Void>()
    let retry = PublishRelay<Void>()
    let query = BehaviorRelay<String>(value: "")
    let delete = PublishRelay<String>()
    let viewModel: WishlistViewModel
    let bag = DisposeBag()
    var state = WishlistViewModel.State()
    var messages: [String] = []

    init() {
        viewModel = WishlistViewModel(repository: repository)
        let output = viewModel.transform(input: .init(
            screenAppeared: appeared.asObservable(), retry: retry.asObservable(),
            searchQuery: query.asObservable(), deleteISBN: delete.asObservable()
        ))
        output.state.drive(onNext: { [weak self] in self?.state = $0 }).disposed(by: bag)
        output.message.emit(onNext: { [weak self] in self?.messages.append($0) }).disposed(by: bag)
    }
}

@MainActor
private final class WishlistStubRepository: WishlistRepositoryProtocol {
    var items = wishlistFixtures()
    var fetchCount = 0
    var deletedISBNs: [String] = []
    var fetchError: Error?
    var deleteError: Error?
    var holdsFetches = false
    var holdsDeletes = false
    var fetches: [CheckedContinuation<[WishlistItem], Error>] = []
    var deletions: [CheckedContinuation<Void, Error>] = []

    func addBook(_ book: Book) async throws { XCTFail("목록 화면은 도서를 추가하지 않습니다") }
    func containsBook(isbn13: String) async throws -> Bool { items.contains { $0.isbn13 == isbn13 } }

    func fetchAllItems() async throws -> [WishlistItem] {
        fetchCount += 1
        if let fetchError { throw fetchError }
        if holdsFetches { return try await withCheckedThrowingContinuation { fetches.append($0) } }
        return items
    }

    func deleteBook(isbn13: String) async throws {
        deletedISBNs.append(isbn13)
        if let deleteError { throw deleteError }
        if holdsDeletes { try await withCheckedThrowingContinuation { deletions.append($0) } }
        items.removeAll { $0.isbn13 == isbn13 }
    }
}
