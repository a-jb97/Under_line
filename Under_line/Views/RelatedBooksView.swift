import RxCocoa
import RxSwift
import SnapKit
import UIKit

final class RelatedBooksView: UIView, UIScrollViewDelegate {
    private let titleLabel = UILabel()
    private let scrollView = UIScrollView()
    private let pageControl = UIPageControl()
    private let stack = UIStackView()
    private let disposeBag = DisposeBag()
    private var pages: [BookDetailInfoView] = []
    private var bookISBNs: [String] = []
    private var lastWidth: CGFloat = 0
    private var currentPageBottom: Constraint?

    var onHeightChange: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isHidden = true
        titleLabel.text = "이 책과 함께 읽기 좋은 책"
        titleLabel.font = UIFont(name: "GoyangIlsanR-Regular", size: 15) ?? .systemFont(ofSize: 15)
        titleLabel.textColor = .accent
        titleLabel.accessibilityTraits.insert(.header)

        scrollView.delegate = self
        scrollView.isPagingEnabled = true
        scrollView.isDirectionalLockEnabled = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.clipsToBounds = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.accessibilityIdentifier = "relatedBooksScrollView"

        pageControl.hidesForSinglePage = true
        pageControl.allowsContinuousInteraction = false
        pageControl.currentPageIndicatorTintColor = .appPrimary
        pageControl.pageIndicatorTintColor = UIColor.appPrimary.withAlphaComponent(0.3)
        pageControl.accessibilityLabel = "추천 도서 페이지"
        pageControl.accessibilityIdentifier = "relatedBooksPageControl"

        stack.axis = .vertical
        stack.spacing = 10
        addSubview(stack)
        [titleLabel, scrollView, pageControl].forEach(stack.addArrangedSubview)
        stack.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            // The parent stack collapses this section to zero height while it is hidden.
            make.bottom.equalToSuperview().priority(998)
        }
        scrollView.contentLayoutGuide.snp.makeConstraints { make in
            make.height.equalTo(scrollView.frameLayoutGuide)
        }

        pageControl.rx.controlEvent(.valueChanged)
            .subscribe(onNext: { [weak self] in
                guard let self else { return }
                self.constrainCurrentPageHeight()
                self.moveToCurrentPage(animated: true)
            })
            .disposed(by: disposeBag)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        guard width > 0, width != lastWidth else { return }
        lastWidth = width
        moveToCurrentPage(animated: false)
    }

    func configure(with books: [Book]) {
        let isbns = books.map(\.isbn13)
        if isbns != bookISBNs {
            rebuildPages(for: isbns)
        }
        isHidden = books.isEmpty
        for (page, book) in zip(pages, books) {
            page.configure(with: book)
        }
    }

    private func rebuildPages(for isbns: [String]) {
        currentPageBottom?.deactivate()
        currentPageBottom = nil
        pages.forEach { $0.removeFromSuperview() }
        bookISBNs = isbns
        pages = isbns.map { _ in BookDetailInfoView() }

        let content = scrollView.contentLayoutGuide
        var previous: BookDetailInfoView?
        for page in pages {
            scrollView.addSubview(page)
            page.onHeightChange = { [weak self] in self?.onHeightChange?() }
            page.snp.makeConstraints { make in
                make.top.equalTo(content)
                make.width.equalTo(scrollView.frameLayoutGuide)
                if let previous {
                    make.leading.equalTo(previous.snp.trailing)
                } else {
                    make.leading.equalTo(content)
                }
            }
            previous = page
        }
        previous?.snp.makeConstraints { make in
            make.trailing.equalTo(content)
        }

        pageControl.numberOfPages = pages.count
        pageControl.currentPage = 0
        pageControl.isHidden = pages.count < 2
        scrollView.isScrollEnabled = pages.count > 1
        scrollView.setContentOffset(.zero, animated: false)
        constrainCurrentPageHeight()
    }

    private func constrainCurrentPageHeight() {
        currentPageBottom?.deactivate()
        guard pages.indices.contains(pageControl.currentPage) else { return }
        // The visible page sets the pager height, including any expanded description.
        pages[pageControl.currentPage].snp.makeConstraints { make in
            currentPageBottom = make.bottom.equalTo(scrollView.contentLayoutGuide).constraint
        }
    }

    private func moveToCurrentPage(animated: Bool) {
        scrollView.setContentOffset(CGPoint(x: CGFloat(pageControl.currentPage) * bounds.width, y: 0),
                                    animated: animated)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        updateCurrentPage()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { updateCurrentPage() }
    }

    private func updateCurrentPage() {
        let width = scrollView.bounds.width
        guard width > 0 else { return }
        let index = Int((scrollView.contentOffset.x / width).rounded())
        guard pages.indices.contains(index), index != pageControl.currentPage else { return }
        pageControl.currentPage = index
        constrainCurrentPageHeight()
    }
}
