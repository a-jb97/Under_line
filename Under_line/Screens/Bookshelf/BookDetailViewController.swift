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
import Kingfisher
import Toast

final class BookDetailViewController: AdaptiveViewController {

    private let book: Book
    private let disposeBag          = DisposeBag()
    private lazy var viewModel      = BookDetailViewModel(
        book:               book,
        sentenceRepository: AppContainer.shared.sentenceRepository
    )
    private let viewWillAppearRelay    = PublishRelay<Void>()
    private let deleteSentenceRelay    = PublishRelay<Sentence>()

    private var sentences: [Sentence] = []
    private var isEditMode = false
    private var currentItemPage: Int?
    private var latestCurrentPage: Int?
    private var flippedSentenceIDs: Set<UUID> = []

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

    // Book Info Section (neumorphic)
    private let bookInfoSection: UIView = {
        let v = UIView()
        v.backgroundColor   = UIColor.background
        v.layer.cornerRadius = 16
        v.layer.shadowColor   = UIColor(hex: "#5d4037").cgColor
        v.layer.shadowOpacity = Float(CGFloat(0x30) / 255)
        v.layer.shadowRadius  = 4
        v.layer.shadowOffset  = CGSize(width: 4, height: 4)
        return v
    }()

    private let bookCoverWidth: CGFloat = 60
    private let bookCoverView: UIImageView = {
        let iv = UIImageView()
        iv.backgroundColor   = UIColor.appPrimary
        iv.layer.cornerRadius = 3
        iv.clipsToBounds      = true
        iv.contentMode        = .scaleAspectFill
        for axis in [NSLayoutConstraint.Axis.horizontal, .vertical] {
            iv.setContentHuggingPriority(.fittingSizeLevel, for: axis)
            iv.setContentCompressionResistancePriority(.fittingSizeLevel, for: axis)
        }
        return iv
    }()

    private let bookTitleLabel: UILabel = {
        let l = UILabel()
        l.text      = "사랑의 기술"
        l.font      = UIFont(name: "GowunBatang-Bold", size: 17)
            ?? .systemFont(ofSize: 17, weight: .bold)
        l.textColor = UIColor.accent
        return l
    }()

    private let bookAuthorLabel: UILabel = {
        let l = UILabel()
        l.text      = "에리히 프롬"
        l.font      = UIFont(name: "GowunBatang-Regular", size: 13)
            ?? .systemFont(ofSize: 13)
        l.textColor = UIColor.appPrimary
        return l
    }()

    private let publisherLabel: UILabel = {
        let l = UILabel()
        l.text      = "문예출판사 · 2023"
        l.font      = UIFont(name: "GoyangIlsan R", size: 11)
            ?? .systemFont(ofSize: 11)
        l.textColor = UIColor.appPrimary.withAlphaComponent(0.5)
        return l
    }()

    private let genreTagView: UIView = {
        let v = UIView()
        v.backgroundColor   = UIColor.appPrimary.withAlphaComponent(0.7)
        v.layer.cornerRadius = 3
        return v
    }()

    private let genreTagLabel: UILabel = {
        let l = UILabel()
        l.text      = "철학/심리학"
        l.font      = UIFont(name: "GoyangIlsan R", size: 10)
            ?? .systemFont(ofSize: 10)
        l.textColor = .white
        return l
    }()

    private lazy var moreButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("더 보기", for: .normal)
        btn.titleLabel?.font = UIFont(name: "GoyangIlsan R", size: 11)
            ?? .systemFont(ofSize: 11)
        btn.setTitleColor(UIColor.appPrimary.withAlphaComponent(0.7), for: .normal)
        btn.contentHorizontalAlignment = .right
        return btn
    }()

    private let descriptionLabel: UILabel = {
        let l = UILabel()
        l.numberOfLines = 0
        l.font = UIFont(name: "GoyangIlsan R", size: 12)
            ?? .systemFont(ofSize: 12)
        l.textColor = UIColor.appPrimary.withAlphaComponent(0.75)
        l.isHidden = true
        return l
    }()

    // Progress Section
    private let progressSectionView = ProgressSectionView()

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
        configureWithBook()
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

        // Book Info Section
        genreTagView.addSubview(genreTagLabel)
        bookInfoSection.addSubview(bookCoverView)
        bookInfoSection.addSubview(bookTitleLabel)
        bookInfoSection.addSubview(bookAuthorLabel)
        bookInfoSection.addSubview(publisherLabel)
        bookInfoSection.addSubview(genreTagView)
        bookInfoSection.addSubview(moreButton)
        bookInfoSection.addSubview(descriptionLabel)

        bookInfoSection.addSubview(progressSectionView)
        contentView.addSubview(bookInfoSection)

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

        updateBookCoverConstraints(aspectRatio: 83 / bookCoverWidth)

        // Book Title
        bookTitleLabel.snp.makeConstraints { make in
            make.leading.equalTo(bookCoverView.snp.leading).offset(bookCoverWidth + 14)
            make.trailing.equalToSuperview().inset(16)
            make.top.equalToSuperview().inset(16)
        }

        bookAuthorLabel.snp.makeConstraints { make in
            make.leading.trailing.equalTo(bookTitleLabel)
            make.top.equalTo(bookTitleLabel.snp.bottom).offset(4)
        }

        publisherLabel.snp.makeConstraints { make in
            make.leading.trailing.equalTo(bookTitleLabel)
            make.top.equalTo(bookAuthorLabel.snp.bottom).offset(4)
        }

        genreTagView.snp.makeConstraints { make in
            make.leading.equalTo(bookTitleLabel)
            make.top.equalTo(publisherLabel.snp.bottom).offset(6)
        }

        genreTagLabel.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 2, left: 8, bottom: 2, right: 8))
        }

        moreButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(16)
            make.centerY.equalTo(genreTagView)
        }

        descriptionLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(16)
            make.top.equalTo(genreTagView.snp.bottom).offset(10)
        }

        // Progress Section (cornerRadius 12, padding [12,14])
        // 도서 소개가 접혀 있으면 장르 태그 하단을 기준으로 배치한다.
        progressSectionView.snp.makeConstraints { make in
            make.top.equalTo(genreTagView.snp.bottom).offset(16)
            make.leading.trailing.equalToSuperview().inset(16)
            make.bottom.equalToSuperview().inset(16)
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

    private func updateBookCoverConstraints(aspectRatio: CGFloat) {
        bookCoverView.snp.remakeConstraints { make in
            make.leading.equalToSuperview().inset(16)
            make.top.greaterThanOrEqualToSuperview().inset(16)
            make.bottom.equalTo(genreTagView.snp.bottom)
            make.width.lessThanOrEqualTo(bookCoverWidth)
            make.width.equalTo(bookCoverWidth).priority(249)
            make.height.equalTo(bookCoverView.snp.width).multipliedBy(aspectRatio)
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
        bookInfoSection.snp.remakeConstraints { make in
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
                make.top.lessThanOrEqualTo(bookInfoSection)
                make.top.equalTo(quoteCard).priority(.low)
                make.top.equalTo(bookInfoSection).priority(.low)
                make.top.greaterThanOrEqualTo(contentView).offset(12)
                make.top.equalTo(contentView).offset(12).priority(247)
                make.bottom.greaterThanOrEqualTo(pageControl)
                make.bottom.greaterThanOrEqualTo(bookInfoSection)
                make.bottom.equalTo(pageControl).priority(.low)
                make.bottom.equalTo(bookInfoSection).priority(.low)
                // 긴 도서 소개는 상단부터 표시하고 하단 버튼 위까지 스크롤할 수 있게 한다.
                make.bottom.lessThanOrEqualTo(contentView).offset(-80)
                make.centerY.equalTo(contentView).offset(-12).priority(248)
            }
        }
    }

    // MARK: - Book Data

    private func configureWithBook() {
        bookTitleLabel.text  = book.displayTitle
        bookAuthorLabel.text = book.author

        var publisherStr = book.publisher
        if let date = book.publishDate, !date.isEmpty {
            publisherStr += " · \(date)"
        }
        publisherLabel.text = publisherStr

        genreTagLabel.text = BookGenre.normalized(book.category)
        genreTagView.isHidden = false

        if let coverURL = book.coverURL {
            let request = ShelfCoverImageSource.request(for: coverURL)
            bookCoverView.kf.setImage(with: request.url, options: request.options) { [weak self] result in
                guard let self, case .success(let value) = result else { return }
                let imageSize = value.image.size
                guard imageSize.width > 0, imageSize.height > 0 else { return }
                self.updateBookCoverConstraints(aspectRatio: imageSize.height / imageSize.width)
            }
        }

        let descStyle = NSMutableParagraphStyle()
        descStyle.lineHeightMultiple = 1.5
        descriptionLabel.attributedText = NSAttributedString(
            string: book.description,
            attributes: [
                .font:            UIFont(name: "GoyangIlsan R", size: 12) ?? .systemFont(ofSize: 12),
                .foregroundColor: UIColor.appPrimary.withAlphaComponent(0.75),
                .paragraphStyle:  descStyle,
            ]
        )
        moreButton.isHidden = book.description.isEmpty
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

        output.errorMessage
            .emit(onNext: { [weak self] message in
                var style = ToastStyle()
                style.backgroundColor = UIColor.appPrimary.withAlphaComponent(0.9)
                style.messageFont = UIFont(name: "GowunBatang-Regular", size: 14) ?? .systemFont(ofSize: 14)
                self?.view.makeToast(message, duration: 1.2, position: .center, style: style)
            })
            .disposed(by: disposeBag)
    }

    // MARK: - Sentences

    private func renderQuotePages() {
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

        tapGesture.rx.event
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
            .disposed(by: disposeBag)

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
                .disposed(by: disposeBag)
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
                cameraVC.onOCRTextExtracted = { [weak self] extractedText in
                    guard let self else { return }
                    let directVC = DirectCollectViewController(
                        bookISBN:        self.book.isbn13,
                        initialSentence: extractedText
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

        moreButton.rx.tap
            .subscribe(onNext: { [weak self] in
                guard let self else { return }
                let isExpanded = !self.descriptionLabel.isHidden
                self.descriptionLabel.isHidden = isExpanded
                self.progressSectionView.snp.remakeConstraints { make in
                    if isExpanded {
                        make.top.equalTo(self.genreTagView.snp.bottom).offset(16)
                    } else {
                        make.top.equalTo(self.descriptionLabel.snp.bottom).offset(16)
                    }
                    make.leading.trailing.equalToSuperview().inset(16)
                    make.bottom.equalToSuperview().inset(16)
                }
                UIView.animate(withDuration: 0.25) {
                    self.view.layoutIfNeeded()
                }
                self.moreButton.setTitle(isExpanded ? "더 보기" : "가리기", for: .normal)
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
                guard let self, !self.sentences.isEmpty else { return }
                let sentence = self.sentences[self.pageControl.currentPage]
                let editorVC = QuoteCardEditorViewController(sentence: sentence, bookTitle: self.book.displayTitle)
                editorVC.modalPresentationStyle = .overFullScreen
                editorVC.modalTransitionStyle   = .crossDissolve
                self.present(editorVC, animated: true)
            })
            .disposed(by: disposeBag)
    }

}

// MARK: - Tutorial

extension BookDetailViewController {
    private func showTutorialIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "tutorial.bookDetail") else { return }

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
            TutorialSupport.barButtonStep(item: timerButton, on: self, message: "타이머 아이콘에서 독서 시간을 기록하고\n통계를 확인하세요"),
        ]

        let tutorialVC = TutorialOverlayViewController()
        tutorialVC.steps = steps
        tutorialVC.modalPresentationStyle = .overFullScreen
        tutorialVC.modalTransitionStyle = .crossDissolve
        tutorialVC.onFinished = {
            UserDefaults.standard.set(true, forKey: "tutorial.bookDetail")
        }
        present(tutorialVC, animated: true)
    }
}

// MARK: - UIScrollViewDelegate

extension BookDetailViewController: UIScrollViewDelegate {
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView === quoteScrollView, scrollView.bounds.width > 0 else { return }
        pageControl.currentPage = Int(scrollView.contentOffset.x / scrollView.bounds.width)
    }
}
