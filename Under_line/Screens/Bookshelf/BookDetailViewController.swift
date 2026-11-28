//
//  BookDetailViewController.swift
//  Under_line
//
//  책 탭 시 push되는 상세 화면 — 나의 밑줄 (Node 9mut1)
//

import UIKit
import SnapKit
import RxSwift
import RxCocoa
import Toast

final class BookDetailViewController: AdaptiveViewController {

    private let book: Book
    private let disposeBag          = DisposeBag()
    private lazy var viewModel      = BookDetailViewModel(
        book:               book,
        sentenceRepository: AppContainer.shared.sentenceRepository,
        bookRepository: AppContainer.shared.bookRepository,
        relatedBooksPreference: AppContainer.shared.relatedBooksPreference
    )
    private let viewWillAppearRelay    = PublishRelay<Void>()
    private let deleteSentenceRelay    = PublishRelay<Sentence>()

    private var sentences: [Sentence] = []
    private var isEditMode = false
    private var currentItemPage: Int?
    private var latestCurrentPage: Int?
    private var flippedSentenceIDs: Set<UUID> = []
    private var quotePageDisposeBag = DisposeBag()

    private let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.showsVerticalScrollIndicator = false
        sv.alwaysBounceVertical = true
        return sv
    }()

    private let contentView = UIView()
    private let viewportLayoutGuide = UILayoutGuide()
    private let columnsLayoutGuide = UILayoutGuide()

    init(book: Book) {
        self.book = book
        currentItemPage = book.itemPage
        latestCurrentPage = book.currentPage
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - UI Components

    // Header

    private let timerButton = SystemNavigationStyle.item(
        image: "timer", label: "독서 타이머", identifier: "readingTimerButton", tint: .appPrimary, priority: .high
    )

    // Quote Card
    private let quoteCard: UIView = {
        let v = UIView()
        v.backgroundColor = .white
        v.layer.cornerRadius = 16
        v.layer.shadowColor   = UIColor.black.cgColor
        v.layer.shadowOpacity = Float(CGFloat(0x26) / 255)
        v.layer.shadowRadius  = 12
        v.layer.shadowOffset  = CGSize(width: 0, height: 8)
        return v
    }()

    private let quoteScrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.isPagingEnabled = true
        sv.showsHorizontalScrollIndicator = false
        sv.clipsToBounds = true
        return sv
    }()

    // Page Control
    private let pageControl: UIPageControl = {
        let pc = UIPageControl()
        pc.currentPageIndicatorTintColor = UIColor.appPrimary
        pc.pageIndicatorTintColor = UIColor.appPrimary.withAlphaComponent(0.3)
        pc.hidesForSinglePage = true
        return pc
    }()

    private let bookSectionsStack = UIStackView()
    private let bookInfoSection = BookDetailViewController.makeBookSection()
    private let relatedBooksSection = BookDetailViewController.makeBookSection()
    private let bookInfoView = BookDetailInfoView()
    private let progressSectionView = ProgressSectionView()
    private let relatedBooksView = RelatedBooksView()
    private let bookInfoStack = UIStackView()

    // 문장 편집 버튼 (BookshelfViewController의 editButton과 동일)
    private lazy var sentenceEditButton: UIButton = {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        btn.setImage(UIImage(systemName: "square.and.pencil", withConfiguration: cfg), for: .normal)
        btn.tintColor = UIColor.appPrimary
        return btn
    }()

    private let sentenceUpdateContainer: UIView = {
        let v = UIView()
        v.isHidden = true
        return v
    }()

    private lazy var sentenceUpdateButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.title = "밑줄 수정"
        config.baseForegroundColor = UIColor.appPrimary
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
            var attrs = attrs
            attrs.font = .systemFont(ofSize: 14, weight: .semibold)
            return attrs
        }
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
        let btn = UIButton(configuration: config)
        return btn
    }()

    // FAB
    private lazy var fabButton: UIButton = {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        btn.setImage(UIImage(systemName: "plus", withConfiguration: cfg), for: .normal)
        btn.tintColor = UIColor.appPrimary
        return btn
    }()

    // MARK: - Lifecycle

    private var lastQuoteWidth: CGFloat = 0
    private var columns: ReadingColumns?

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        let layout = ReadingColumns(
            container: ContainerLayout(view: view, reservesInactiveDivisions: true),
            usesFullWidth: traitCollection.userInterfaceIdiom == .pad
        )
        guard layout != columns else { return }
        columns = layout
        updateContentConstraints()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = quoteScrollView.bounds.width
        guard width > 0, width != lastQuoteWidth else { return }
        lastQuoteWidth = width
        quoteScrollView.setContentOffset(CGPoint(x: CGFloat(pageControl.currentPage) * width, y: 0), animated: false)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupConstraints()
        bookInfoView.configure(with: book)
        progressSectionView.configure(
            itemPage: currentItemPage,
            currentPage: latestCurrentPage
        )
        bindViewModel()
        bindActions()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewWillAppearRelay.accept(())
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        showTutorialIfNeeded()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }

    // MARK: - Setup

    private static func makeBookSection() -> UIView {
        let section = UIView()
        section.backgroundColor = .background
        section.layer.cornerRadius = 16
        section.layer.shadowColor = UIColor(hex: "#5d4037").cgColor
        section.layer.shadowOpacity = Float(CGFloat(0x30) / 255)
        section.layer.shadowRadius = 4
        section.layer.shadowOffset = CGSize(width: 4, height: 4)
        return section
    }

    private func setupUI() {
        SystemNavigationStyle.configure(self, title: "나의 밑줄")
        SystemNavigationStyle.setTrailingItems([timerButton], on: navigationItem)
        view.backgroundColor = UIColor.background

        // Scroll container
        view.addLayoutGuide(viewportLayoutGuide)
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addLayoutGuide(columnsLayoutGuide)

        // Quote Card
        quoteScrollView.delegate = self
        quoteCard.addSubview(quoteScrollView)
        contentView.addSubview(quoteCard)
        contentView.addSubview(pageControl)

        bookInfoStack.axis = .vertical
        bookInfoStack.spacing = 16
        bookInfoStack.addArrangedSubview(bookInfoView)
        bookInfoStack.addArrangedSubview(progressSectionView)
        bookInfoSection.addSubview(bookInfoStack)
        relatedBooksSection.isHidden = true
        relatedBooksSection.addSubview(relatedBooksView)

        bookSectionsStack.axis = .vertical
        bookSectionsStack.spacing = 24
        bookSectionsStack.addArrangedSubview(bookInfoSection)
        bookSectionsStack.addArrangedSubview(relatedBooksSection)
        contentView.addSubview(bookSectionsStack)
        let updateBookInfoHeight: () -> Void = { [weak self] in
            self?.view.setNeedsLayout()
            UIView.animate(withDuration: 0.25) {
                self?.view.layoutIfNeeded()
            }
        }
        bookInfoView.onHeightChange = updateBookInfoHeight
        relatedBooksView.onHeightChange = updateBookInfoHeight

        // FAB
        view.addSubview(fabButton)
        view.addSubview(sentenceEditButton)
        view.addSubview(sentenceUpdateContainer)
        sentenceUpdateContainer.addSubview(sentenceUpdateButton)

        SystemGlassButtonStyle.apply(to: fabButton, accessibilityLabel: "밑줄 추가")
        SystemGlassButtonStyle.apply(to: sentenceEditButton, accessibilityLabel: "밑줄 편집")
        SystemGlassButtonStyle.apply(to: sentenceUpdateButton, accessibilityLabel: "밑줄 수정")
    }

    private func setupConstraints() {
        // Scroll container
        updateContentConstraints()
        scrollView.snp.makeConstraints { make in
            make.edges.equalTo(viewportLayoutGuide)
        }

        quoteScrollView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        // Page Control
        pageControl.snp.makeConstraints { make in
            make.top.equalTo(quoteCard.snp.bottom).offset(16)
            make.centerX.equalTo(quoteCard)
        }

        bookInfoStack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(16)
        }
        relatedBooksView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview().inset(16)
            make.bottom.equalToSuperview().inset(16).priority(999)
        }

        // FAB (52×52, trailing 24, bottom safeArea 16)
        fabButton.snp.makeConstraints { make in
            make.trailing.equalTo(viewportLayoutGuide).inset(24)
            make.bottom.equalTo(viewportLayoutGuide).inset(16)
            make.size.equalTo(52)
        }

        sentenceEditButton.snp.makeConstraints { make in
            make.leading.equalTo(viewportLayoutGuide).offset(24)
            make.centerY.equalTo(fabButton)
            make.size.equalTo(52)
        }

        sentenceUpdateContainer.snp.makeConstraints { make in
            make.leading.equalTo(sentenceEditButton.snp.trailing).offset(12)
            make.trailing.lessThanOrEqualTo(fabButton.snp.leading).offset(-12)
            make.centerY.equalTo(sentenceEditButton)
            make.height.equalTo(52)
        }

        sentenceUpdateButton.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    private func updateContentConstraints() {
        scrollView.contentInset.bottom = columns == nil ? 80 : 0
        viewportLayoutGuide.snp.remakeConstraints { make in
            if let columns {
                make.left.equalTo(view).offset(columns.viewport.minX)
                make.top.equalTo(view).offset(columns.viewport.minY)
                make.width.equalTo(columns.viewport.width)
                make.height.equalTo(columns.viewport.height)
            } else {
                make.edges.equalTo(view.adaptiveContentLayoutGuide)
            }
        }
        quoteCard.snp.remakeConstraints { make in
            make.left.equalToSuperview().offset(24)
            if let columns {
                make.width.equalTo(columns.leadingWidth)
            } else {
                make.top.equalToSuperview().offset(12)
                make.right.equalToSuperview().inset(24)
            }
            make.height.equalTo(quoteCard.snp.width).multipliedBy(0.7).priority(.high)
            make.height.lessThanOrEqualTo(scrollView.frameLayoutGuide.snp.height).multipliedBy(0.65)
        }
        bookSectionsStack.snp.remakeConstraints { make in
            make.right.equalToSuperview().inset(24)
            if let columns {
                make.left.equalTo(quoteCard.snp.right).offset(columns.gap)
                make.centerY.equalTo(quoteCard)
            } else {
                make.left.equalTo(quoteCard)
                make.top.equalTo(pageControl.snp.bottom).offset(24)
                make.bottom.equalToSuperview().inset(24)
            }
        }
        contentView.snp.remakeConstraints { make in
            make.edges.equalTo(scrollView.contentLayoutGuide)
            make.width.equalTo(scrollView.frameLayoutGuide)
            if columns != nil {
                make.height.greaterThanOrEqualTo(scrollView.frameLayoutGuide)
                make.height.equalTo(scrollView.frameLayoutGuide).priority(249)
            }
        }
        columnsLayoutGuide.snp.remakeConstraints { make in
            if columns != nil {
                make.leading.trailing.equalTo(contentView)
                make.top.lessThanOrEqualTo(quoteCard)
                make.top.lessThanOrEqualTo(bookSectionsStack)
                make.top.equalTo(quoteCard).priority(.low)
                make.top.equalTo(bookSectionsStack).priority(.low)
                make.top.greaterThanOrEqualTo(contentView).offset(12)
                make.top.equalTo(contentView).offset(12).priority(247)
                make.bottom.greaterThanOrEqualTo(pageControl)
                make.bottom.greaterThanOrEqualTo(bookSectionsStack)
                make.bottom.equalTo(pageControl).priority(.low)
                make.bottom.equalTo(bookSectionsStack).priority(.low)
                // 긴 도서 소개는 상단부터 표시하고 하단 버튼 위까지 스크롤할 수 있게 한다.
                make.bottom.lessThanOrEqualTo(contentView).offset(-80)
                make.centerY.equalTo(contentView).offset(-12).priority(248)
            }
        }
    }

    // MARK: - ViewModel Binding

    private func bindViewModel() {
        let output = viewModel.transform(input: BookDetailViewModel.Input(
            viewWillAppear:    viewWillAppearRelay.asObservable(),
            deleteSentence:    deleteSentenceRelay.asObservable()
        ))

        output.sentences
            .drive(onNext: { [weak self] sentences in
                guard let self else { return }
                self.sentences = sentences
                self.renderQuotePages()
            })
            .disposed(by: disposeBag)

        output.relatedBooks
            .drive(onNext: { [weak self] books in
                self?.configureRelatedBooks(books)
            })
            .disposed(by: disposeBag)

        output.errorMessage
            .emit(onNext: { [weak self] message in
                var style = ToastStyle()
                style.backgroundColor = UIColor.appPrimary.withAlphaComponent(0.9)
                style.messageFont = UIFont(name: "GowunBatang-Regular", size: 14) ?? .systemFont(ofSize: 14)
                self?.view.makeToast(message, duration: 1.2, position: .center, style: style)
            })
            .disposed(by: disposeBag)
    }

    func configureRelatedBooks(_ books: [Book]) {
        relatedBooksView.configure(with: books)
        relatedBooksSection.isHidden = books.isEmpty
    }

    // MARK: - Sentences

    private func renderQuotePages() {
        quotePageDisposeBag = DisposeBag()
        quoteScrollView.subviews.forEach { $0.removeFromSuperview() }

        guard !sentences.isEmpty else {
            let placeholder = makePlaceholderPage()
            quoteScrollView.addSubview(placeholder)
            placeholder.snp.makeConstraints { make in
                make.edges.equalToSuperview()
                make.width.height.equalTo(quoteScrollView)
            }
            pageControl.numberOfPages = 0
            return
        }

        pageControl.numberOfPages = sentences.count
        pageControl.currentPage = 0

        var prev: UIView? = nil
        for (i, sentence) in sentences.enumerated() {
            let page = makePageView(for: sentence)
            quoteScrollView.addSubview(page)
            page.snp.makeConstraints { make in
                make.top.bottom.equalToSuperview()
                make.width.height.equalTo(quoteScrollView)
                if let prev = prev {
                    make.leading.equalTo(prev.snp.trailing)
                } else {
                    make.leading.equalToSuperview()
                }
                if i == sentences.count - 1 {
                    make.trailing.equalToSuperview()
                }
            }
            prev = page
        }
    }

    private func setEditMode(_ editing: Bool) {
        isEditMode = editing
        SystemGlassButtonStyle.setEditing(editing, on: sentenceEditButton, accessibilityLabel: "밑줄 편집")
        sentenceUpdateContainer.isHidden = !editing
        renderQuotePages()
    }

    private func deleteSentence(_ sentence: Sentence) {
        deleteSentenceRelay.accept(sentence)
        WidgetCacheService.shared.refreshCache()
    }

    private func makePageView(for sentence: Sentence) -> UIView {
        let page = UIView()

        // ── Front view (문장) ──────────────────────────────────
        let frontView = UIView()
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.2
        style.alignment = .center

        let textLabel = UILabel()
        textLabel.numberOfLines = 0
        textLabel.textAlignment = .center
        textLabel.attributedText = NSAttributedString(
            string: sentence.sentence,
            attributes: [
                .font:            UIFont(name: "GowunBatang-Regular", size: 18) ?? .systemFont(ofSize: 18),
                .foregroundColor: UIColor.appPrimary,
                .paragraphStyle:  style,
            ]
        )

        let pageLabel = UILabel()
        pageLabel.text = "p.\(sentence.page)"
        pageLabel.font = UIFont(name: "GoyangIlsan R", size: 13) ?? .systemFont(ofSize: 13)
        pageLabel.textColor = UIColor.appPrimary.withAlphaComponent(0.5)
        pageLabel.textAlignment = .right

        let emotionImageView = UIImageView(image: sentence.emotion.emoji)
        emotionImageView.contentMode = .scaleAspectFit

        // ── Step 1: textAreaView로 감정/페이지 겹침 방지 ──────────
        // ── Step 2: UIScrollView로 긴 문장 스크롤 지원 ─────────────
        let textScrollView = UIScrollView()
        textScrollView.showsVerticalScrollIndicator = false
        textScrollView.showsHorizontalScrollIndicator = false
        textScrollView.alwaysBounceVertical = false

        let textContentView = UIView()
        textScrollView.addSubview(textContentView)
        textContentView.addSubview(textLabel)

        // textAreaView: pageLabel/emotionImageView 위쪽 공간만 차지
        let textAreaView = UIView()
        textAreaView.clipsToBounds = true
        textAreaView.addSubview(textScrollView)

        frontView.addSubview(pageLabel)
        frontView.addSubview(emotionImageView)
        frontView.addSubview(textAreaView)

        pageLabel.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(24)
            make.bottom.equalToSuperview().inset(20)
        }
        emotionImageView.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(20)
            make.bottom.equalToSuperview().inset(16)
            make.size.equalTo(18)
        }
        // textAreaView: 상단 20pt ~ pageLabel 위 8pt
        textAreaView.snp.makeConstraints { make in
            make.top.equalToSuperview().inset(20)
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(pageLabel.snp.top).offset(-8)
        }
        // textContentView: 스크롤 콘텐츠 영역, 너비는 scrollView frame에 고정
        textContentView.snp.makeConstraints { make in
            make.edges.equalTo(textScrollView.contentLayoutGuide)
            make.width.equalTo(textScrollView.frameLayoutGuide)
        }
        textLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(24)
            make.top.bottom.equalToSuperview()
        }
        // textScrollView: 콘텐츠 높이에 맞추되(medium), textAreaView 초과 불가
        // 짧은 문장은 textAreaView 내 수직 중앙, 긴 문장은 전체 영역 채우고 스크롤
        textScrollView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.centerY.equalToSuperview()
            make.height.lessThanOrEqualToSuperview()
            make.height.equalTo(textContentView).priority(.medium)
        }

        page.addSubview(frontView)
        frontView.snp.makeConstraints { make in make.edges.equalToSuperview() }

        // ── Back view (메모) ───────────────────────────────────
        let backView = UIView()

        let memoStyle = NSMutableParagraphStyle()
        memoStyle.lineHeightMultiple = 1.5
        memoStyle.alignment = .center

        let memoLabel = UILabel()
        memoLabel.numberOfLines = 0
        memoLabel.textAlignment = .center
        if let memo = sentence.memo, !memo.isEmpty {
            memoLabel.attributedText = NSAttributedString(
                string: memo,
                attributes: [
                    .font:            UIFont(name: "GowunBatang-Regular", size: 16) ?? .systemFont(ofSize: 16),
                    .foregroundColor: UIColor.appPrimary,
                    .paragraphStyle:  memoStyle,
                ]
            )
        } else {
            memoLabel.attributedText = NSAttributedString(
                string: "등록된 메모 없음",
                attributes: [
                    .font:            UIFont(name: "GowunBatang-Regular", size: 16) ?? .systemFont(ofSize: 16),
                    .foregroundColor: UIColor.appPrimary.withAlphaComponent(0.35),
                    .paragraphStyle:  memoStyle,
                ]
            )
        }

        let memoScroll = ScrollableTextView(label: memoLabel)
        backView.addSubview(memoScroll)
        memoScroll.snp.makeConstraints { $0.edges.equalToSuperview().inset(12) }

        page.addSubview(backView)
        backView.snp.makeConstraints { make in make.edges.equalToSuperview() }

        // 초기 flip 상태 반영
        let isFlipped = flippedSentenceIDs.contains(sentence.id)
        frontView.isHidden = isFlipped
        backView.isHidden  = !isFlipped

        // ── 카드 플립 탭 제스처 ────────────────────────────────────
        // UIButton(edges: equalToSuperview)은 textScrollView의 pan 제스처를 가로채므로
        // cancelsTouchesInView = false 인 UITapGestureRecognizer 사용
        let tapGesture = UITapGestureRecognizer()
        tapGesture.cancelsTouchesInView = false
        page.addGestureRecognizer(tapGesture)

        if !isEditMode, let photoData = sentence.markedPhotoData {
            let doubleTap = UITapGestureRecognizer()
            doubleTap.numberOfTapsRequired = 2
            doubleTap.cancelsTouchesInView = false
            page.addGestureRecognizer(doubleTap)
            tapGesture.require(toFail: doubleTap)
            doubleTap.rx.event
                .filter { $0.state == .recognized }
                .subscribe(onNext: { [weak self] _ in
                    guard let self, self.presentedViewController == nil else { return }
                    guard let preview = QuoteCardEditorViewController(markedPhotoData: photoData) else {
                        self.view.makeToast("밑줄 사진을 열지 못했어요.", position: .center)
                        return
                    }
                    self.presentCardOverlay(preview)
                })
                .disposed(by: quotePageDisposeBag)
        }

        tapGesture.rx.event
            .filter { $0.state == .recognized }
            .subscribe(onNext: { [weak self, weak page, weak frontView, weak backView] _ in
                guard let self, let page, let frontView, let backView,
                      !self.isEditMode else { return }
                let nowFlipped = self.flippedSentenceIDs.contains(sentence.id)
                if nowFlipped {
                    self.flippedSentenceIDs.remove(sentence.id)
                } else {
                    self.flippedSentenceIDs.insert(sentence.id)
                }
                let toFlip = !nowFlipped
                UIView.transition(with: page, duration: 0.45, options: .transitionFlipFromRight, animations: {
                    frontView.isHidden = toFlip
                    backView.isHidden  = !toFlip
                }, completion: nil)
            })
            .disposed(by: quotePageDisposeBag)

        // ── 편집 모드 삭제 버튼 (탭 버튼 위) ─────────────────────
        if isEditMode {
            let deleteButton = UIButton(type: .system)
            let cfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            deleteButton.setImage(UIImage(systemName: "minus.circle.fill", withConfiguration: cfg), for: .normal)
            deleteButton.tintColor = .systemRed
            page.addSubview(deleteButton)
            deleteButton.snp.makeConstraints { make in
                make.top.equalToSuperview().inset(12)
                make.trailing.equalToSuperview().inset(12)
                make.size.equalTo(28)
            }
            deleteButton.rx.tap
                .subscribe(onNext: { [weak self] in
                    self?.deleteSentence(sentence)
                })
                .disposed(by: quotePageDisposeBag)
        }

        return page
    }

    private func makePlaceholderPage() -> UIView {
        let page = UIView()
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.2
        style.alignment = .center

        let textLabel = UILabel()
        textLabel.numberOfLines = 0
        textLabel.textAlignment = .center
        textLabel.attributedText = NSAttributedString(
            string: "첫 밑줄을 등록해보세요.",
            attributes: [
                .font:            UIFont(name: "GowunBatang-Regular", size: 18) ?? .systemFont(ofSize: 18),
                .foregroundColor: UIColor.appPrimary,
                .paragraphStyle:  style,
            ]
        )
        page.addSubview(textLabel)
        textLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(24)
            make.center.equalToSuperview()
        }
        return page
    }

    private func loadSentences() {
        viewWillAppearRelay.accept(())
    }

    // MARK: - Bindings

    private func bindActions() {

        fabButton.rx.tap
            .subscribe(onNext: { [weak self] in
                guard let self else { return }
                let cameraVC = CameraCollectionViewController()
                let cameraNavigation = UINavigationController(rootViewController: cameraVC)
                SystemNavigationStyle.configure(cameraNavigation)
                cameraNavigation.modalPresentationStyle = .fullScreen

                // 직접 수집 버튼 → OCR 없이 빈 폼으로 present
                cameraVC.onDirectCollect = { [weak self] in
                    guard let self else { return }
                    let directVC = DirectCollectViewController(bookISBN: self.book.isbn13)
                    directVC.modalPresentationStyle = .pageSheet
                    directVC.onSaved = { [weak self] in self?.loadSentences() }
                    self.present(directVC, animated: true)
                }

                // 수집하기(촬영) → OCR 텍스트 추출 후 pre-fill
                cameraVC.onMarkupConfirmed = { [weak self] extractedText, photoData in
                    guard let self else { return }
                    let directVC = DirectCollectViewController(
                        bookISBN:        self.book.isbn13,
                        initialSentence: extractedText,
                        markedPhotoData: photoData
                    )
                    directVC.modalPresentationStyle = .pageSheet
                    directVC.onSaved = { [weak self] in self?.loadSentences() }
                    self.present(directVC, animated: true)
                }

                self.present(cameraNavigation, animated: true)
            })
            .disposed(by: disposeBag)

        timerButton.rx.tap
            .subscribe(onNext: { [weak self] in
                guard let self else { return }
                let vc = ReadingRecordViewController(
                    book:            self.book,
                    currentItemPage: self.currentItemPage,
                    initialPage:     self.latestCurrentPage
                )
                vc.onProgressRecorded = { [weak self] progress in
                    guard let self else { return }
                    self.currentItemPage = progress.itemPage
                    self.latestCurrentPage = progress.currentPage
                    self.progressSectionView.configure(
                        itemPage: progress.itemPage,
                        currentPage: progress.currentPage
                    )
                }
                self.navigationController?.pushViewController(vc, animated: true)
            })
            .disposed(by: disposeBag)

        progressSectionView.editButtonTap
            .subscribe(onNext: { [weak self] in
                guard let self else { return }
                let vc = PageRecordViewController(
                    isbn13: self.book.isbn13,
                    itemPage: self.currentItemPage,
                    currentPage: self.latestCurrentPage
                )
                vc.modalPresentationStyle = .pageSheet
                vc.onProgressRecorded = { [weak self] progress in
                    guard let self else { return }
                    self.currentItemPage = progress.itemPage
                    self.latestCurrentPage = progress.currentPage
                    self.progressSectionView.configure(
                        itemPage: progress.itemPage,
                        currentPage: progress.currentPage
                    )
                }
                self.present(vc, animated: true)
            })
            .disposed(by: disposeBag)

        sentenceEditButton.rx.tap
            .subscribe(onNext: { [weak self] in
                guard let self else { return }
                self.setEditMode(!self.isEditMode)
            })
            .disposed(by: disposeBag)

        sentenceUpdateButton.rx.tap
            .subscribe(onNext: { [weak self] in
                guard let self else { return }
                let idx = self.pageControl.currentPage
                guard idx < self.sentences.count else { return }
                let vc = DirectCollectViewController(editing: self.sentences[idx])
                vc.onSaved = { [weak self] in self?.loadSentences() }
                vc.modalPresentationStyle = .pageSheet
                self.present(vc, animated: true)
            })
            .disposed(by: disposeBag)

        // quoteCard 길게 탭 → 카드 편집 오버레이
        // Rule 1 예외: long press는 UIButton으로 대체 불가 → UILongPressGestureRecognizer + rx.event 사용
        let longPress = UILongPressGestureRecognizer()
        longPress.minimumPressDuration = 0.5
        quoteCard.addGestureRecognizer(longPress)
        longPress.rx.event
            .filter { $0.state == .began }
            .subscribe(onNext: { [weak self] _ in
                guard let self, self.presentedViewController == nil,
                      self.sentences.indices.contains(self.pageControl.currentPage) else { return }
                let sentence = self.sentences[self.pageControl.currentPage]
                let editorVC = QuoteCardEditorViewController(sentence: sentence, bookTitle: self.book.displayTitle)
                self.presentCardOverlay(editorVC)
            })
            .disposed(by: disposeBag)
    }

    private func presentCardOverlay(_ controller: QuoteCardEditorViewController) {
        controller.modalPresentationStyle = .overFullScreen
        controller.modalTransitionStyle = .crossDissolve
        present(controller, animated: true)
    }

}

// MARK: - Tutorial

extension BookDetailViewController {
    private func showTutorialIfNeeded() {
        let markedPhotoStep = TutorialSupport.viewStep(
            target: quoteCard,
            message: "촬영한 밑줄을 등록하면 사진도 함께 저장돼요.\n해당 카드를 두 번 탭해 사진을 열어보세요."
        )
        guard !UserDefaults.standard.bool(forKey: "tutorial.bookDetail") else {
            TutorialSupport.show(on: self, key: TutorialSupport.markedPhotoCardKey, steps: [markedPhotoStep])
            return
        }

        let steps: [TutorialStep] = [
            TutorialStep(
                targetFrame: .zero,
                message: "카메라 OCR이나 직접 입력으로\n밑줄을 수집해보세요!",
                targetFrameProvider: { [weak self] in
                    guard let target = self?.fabButton else { return .zero }
                    return target.convert(target.bounds, to: nil)
                }
            ),
            TutorialStep(
                targetFrame: .zero,
                message: "카드를 탭하면 앞뒷면이 뒤집혀요\n앞면은 문장, 뒷면은 메모예요",
                targetFrameProvider: { [weak self] in
                    guard let target = self?.quoteCard else { return .zero }
                    return target.convert(target.bounds, to: nil)
                }
            ),
            TutorialStep(
                targetFrame: .zero,
                message: "카드를 길게 탭하면\n이미지 카드로 만들어 저장할 수 있어요",
                targetFrameProvider: { [weak self] in
                    guard let target = self?.quoteCard else { return .zero }
                    return target.convert(target.bounds, to: nil)
                }
            ),
            markedPhotoStep,
            TutorialSupport.barButtonStep(item: timerButton, on: self, message: "타이머 아이콘에서 독서 시간을 기록하고\n통계를 확인하세요"),
        ]

        TutorialSupport.show(on: self, key: "tutorial.bookDetail", steps: steps) {
            UserDefaults.standard.set(true, forKey: TutorialSupport.markedPhotoCardKey)
        }
    }
}

// MARK: - UIScrollViewDelegate

extension BookDetailViewController: UIScrollViewDelegate {
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView === quoteScrollView, scrollView.bounds.width > 0 else { return }
        pageControl.currentPage = Int(scrollView.contentOffset.x / scrollView.bounds.width)
    }
}
