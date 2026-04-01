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

final class BookDetailViewController: UIViewController {

    private let book: Book
    private let disposeBag          = DisposeBag()
    private lazy var viewModel      = BookDetailViewModel(
        book:               book,
        sentenceRepository: AppContainer.shared.sentenceRepository,
        bookRepository:     AppContainer.shared.bookRepository
    )
    private let viewWillAppearRelay    = PublishRelay<Void>()
    private let deleteSentenceRelay    = PublishRelay<Sentence>()
    private let updateCurrentPageRelay = PublishRelay<Int>()

    private var sentences: [Sentence] = []
    private var highlightLayers: [(view: UIView, layer: CAGradientLayer)] = []
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

    init(book: Book) {
        self.book = book
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - UI Components

    // Header
    private lazy var backButton: UIButton = {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        btn.setImage(UIImage(systemName: "chevron.left", withConfiguration: cfg), for: .normal)
        btn.tintColor = UIColor.accent
        return btn
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.text = "나의 밑줄"
        l.font = UIFont(name: "GowunBatang-Bold", size: 34)
            ?? .systemFont(ofSize: 34, weight: .bold)
        l.textColor = UIColor.accent
        return l
    }()

    private lazy var timerButton: UIButton = {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        btn.setImage(UIImage(systemName: "timer", withConfiguration: cfg), for: .normal)
        btn.tintColor = UIColor.appPrimary
        btn.layer.cornerRadius = 20
        btn.clipsToBounds = true
        return btn
    }()

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

    private let bookCoverView: UIImageView = {
        let iv = UIImageView()
        iv.backgroundColor   = UIColor.appPrimary
        iv.layer.cornerRadius = 3
        iv.clipsToBounds      = true
        iv.contentMode        = .scaleAspectFill
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
        btn.tintColor = UIColor.walnut
        btn.layer.cornerRadius = 26
        btn.clipsToBounds = true
        return btn
    }()

    // FAB
    private lazy var fabButton: UIButton = {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        btn.setImage(UIImage(systemName: "plus", withConfiguration: cfg), for: .normal)
        btn.tintColor = UIColor.walnut
        btn.layer.cornerRadius = 26
        btn.clipsToBounds = true
        return btn
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupConstraints()
        configureWithBook()
        bindViewModel()
        bindActions()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.interactivePopGestureRecognizer?.delegate = nil
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        viewWillAppearRelay.accept(())
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        showTutorialIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        for (view, gradient) in highlightLayers {
            gradient.frame = view.bounds
        }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = UIColor.background

        // Header
        view.addSubview(backButton)
        view.addSubview(titleLabel)
        view.addSubview(timerButton)

        // Scroll container
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)

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

        applyFabGlassStyle(to: timerButton,        cornerRadius: 20)
        applyFabGlassStyle(to: fabButton,          cornerRadius: 26)
        applyFabGlassStyle(to: sentenceEditButton, cornerRadius: 26)
    }

    private func setupConstraints() {
        // Header (design: 헤더 높이 ≈ 62, top = safeArea)
        backButton.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(24)
            make.top.equalTo(view.safeAreaLayoutGuide).offset(17)
            make.size.equalTo(28)
        }

        titleLabel.snp.makeConstraints { make in
            make.leading.equalTo(backButton.snp.trailing).offset(4)
            make.centerY.equalTo(backButton)
        }

        timerButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(24)
            make.centerY.equalTo(backButton)
            make.size.equalTo(40)
        }

        // Scroll container
        scrollView.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(8)
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide)
        }
        scrollView.contentInset.bottom = 80

        contentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.width.equalTo(scrollView)
        }

        // Quote Card (height: 266, padding: [24,24,20,24])
        let quoteCardWidthInset: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 100 : 24
        quoteCard.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(12)
            make.leading.trailing.equalToSuperview().inset(quoteCardWidthInset)
            make.height.equalTo(quoteCard.snp.width).multipliedBy(0.7)
        }

        quoteScrollView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        // Page Control
        pageControl.snp.makeConstraints { make in
            make.top.equalTo(quoteCard.snp.bottom).offset(16)
            make.centerX.equalToSuperview()
        }

        // Book Info Section (cornerRadius 16, padding 16, gap 20)
        bookInfoSection.snp.makeConstraints { make in
            make.top.equalTo(pageControl.snp.bottom).offset(24)
            make.leading.trailing.equalToSuperview().inset(24)
            make.bottom.equalToSuperview().inset(24)
        }

        // Book Cover (60×83)
        bookCoverView.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(16)
            make.top.equalToSuperview().inset(16)
            make.width.equalTo(60)
            make.height.equalTo(83)
        }

        // Book Title
        bookTitleLabel.snp.makeConstraints { make in
            make.leading.equalTo(bookCoverView.snp.trailing).offset(14)
            make.trailing.equalToSuperview().inset(16)
            make.top.equalTo(bookCoverView)
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
        // 초기에는 description이 숨겨진 상태이므로 genreTagView 기준
        progressSectionView.snp.makeConstraints { make in
            make.top.equalTo(genreTagView.snp.bottom).offset(16)
            make.leading.trailing.equalToSuperview().inset(16)
            make.bottom.equalToSuperview().inset(16)
        }

        // FAB (52×52, trailing 24, bottom safeArea 16)
        fabButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(24)
            make.bottom.equalTo(view.safeAreaLayoutGuide).inset(16)
            make.size.equalTo(52)
        }

        sentenceEditButton.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(24)
            make.centerY.equalTo(fabButton)
            make.size.equalTo(52)
        }
    }

    // MARK: - Book Data

    private func configureWithBook() {
        bookTitleLabel.text  = book.title
        bookAuthorLabel.text = book.author

        var publisherStr = book.publisher
        if let date = book.publishDate, !date.isEmpty {
            publisherStr += " · \(date)"
        }
        publisherLabel.text = publisherStr

        if let category = book.category, !category.isEmpty {
            genreTagLabel.text    = category
            genreTagView.isHidden = false
        } else {
            genreTagView.isHidden = true
        }

        if let coverURL = book.coverURL {
            bookCoverView.kf.setImage(with: coverURL) { [weak self] result in
                guard let self, case .success(let value) = result else { return }
                let imageSize = value.image.size
                guard imageSize.width > 0 else { return }
                let newHeight = ceil(60.0 * imageSize.height / imageSize.width)
                self.bookCoverView.snp.updateConstraints { make in
                    make.height.equalTo(newHeight)
                }
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
            deleteSentence:    deleteSentenceRelay.asObservable(),
            updateCurrentPage: updateCurrentPageRelay.asObservable()
        ))

        output.sentences
            .drive(onNext: { [weak self] sentences in
                guard let self else { return }
                self.sentences = sentences
                self.renderQuotePages()
            })
            .disposed(by: disposeBag)

        output.itemPage
            .drive(onNext: { [weak self] itemPage in
                guard let self, let itemPage else { return }
                self.currentItemPage = itemPage
                if let currentPage = self.book.currentPage, currentPage > 0 {
                    self.latestCurrentPage = currentPage
                    self.progressSectionView.configure(currentPage: currentPage, itemPage: itemPage)
                } else {
                    self.progressSectionView.showNoProgress(itemPage: itemPage)
                }
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
        if editing {
            sentenceEditButton.setImage(nil, for: .normal)
            sentenceEditButton.setTitle("완료", for: .normal)
            sentenceEditButton.setTitleColor(UIColor.walnut, for: .normal)
            sentenceEditButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        } else {
            let cfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            sentenceEditButton.setImage(UIImage(systemName: "square.and.pencil", withConfiguration: cfg), for: .normal)
            sentenceEditButton.setTitle(nil, for: .normal)
        }
        renderQuotePages()
    }

    private func deleteSentence(_ sentence: Sentence) {
        deleteSentenceRelay.accept(sentence)
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

        frontView.addSubview(textLabel)
        frontView.addSubview(pageLabel)
        frontView.addSubview(emotionImageView)

        textLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(24)
            make.center.equalToSuperview()
        }
        pageLabel.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(24)
            make.bottom.equalToSuperview().inset(20)
        }
        emotionImageView.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(20)
            make.bottom.equalToSuperview().inset(16)
            make.size.equalTo(18)
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

        backView.addSubview(memoLabel)

        memoLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(24)
            make.center.equalToSuperview()
        }

        page.addSubview(backView)
        backView.snp.makeConstraints { make in make.edges.equalToSuperview() }

        // 초기 flip 상태 반영
        let isFlipped = flippedSentenceIDs.contains(sentence.id)
        frontView.isHidden = isFlipped
        backView.isHidden  = !isFlipped

        // ── 탭 버튼 (전체 영역, 편집 모드에서는 비활성) ──────────
        let tapButton = UIButton(type: .system)
        tapButton.backgroundColor = .clear
        page.addSubview(tapButton)
        tapButton.snp.makeConstraints { make in make.edges.equalToSuperview() }

        tapButton.rx.tap
            .subscribe(onNext: { [weak self, weak page, weak frontView, weak backView] in
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

    // MARK: - FAB Glass Style (BookshelfViewController와 동일한 스펙)

    private func applyFabGlassStyle(to button: UIButton, cornerRadius: CGFloat) {
        guard let superview = button.superview else { return }

        let shadowView = UIView()
        shadowView.isUserInteractionEnabled = false
        shadowView.layer.cornerRadius = cornerRadius
        shadowView.backgroundColor = .white
        shadowView.layer.shadowColor   = UIColor.black.cgColor
        shadowView.layer.shadowOpacity = Float(CGFloat(0x18) / 255)
        shadowView.layer.shadowRadius  = 8
        shadowView.layer.shadowOffset  = CGSize(width: 0, height: 6)
        superview.insertSubview(shadowView, belowSubview: button)
        shadowView.snp.makeConstraints { $0.edges.equalTo(button) }

        let glassContainer = UIView()
        glassContainer.isUserInteractionEnabled = false
        glassContainer.layer.cornerRadius = cornerRadius
        glassContainer.clipsToBounds = true
        glassContainer.layer.borderWidth = 1
        glassContainer.layer.borderColor = UIColor(white: 1, alpha: CGFloat(0x70) / 255).cgColor
        superview.insertSubview(glassContainer, belowSubview: button)
        glassContainer.snp.makeConstraints { $0.edges.equalTo(button) }
        superview.insertSubview(shadowView, belowSubview: glassContainer)

        let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        blurView.isUserInteractionEnabled = false
        glassContainer.addSubview(blurView)
        blurView.snp.makeConstraints { $0.edges.equalToSuperview() }

        let solidTint = UIView()
        solidTint.isUserInteractionEnabled = false
        solidTint.backgroundColor = UIColor(hex: "#832C11", alpha: CGFloat(0x24) / 255)
        blurView.contentView.addSubview(solidTint)
        solidTint.snp.makeConstraints { $0.edges.equalToSuperview() }

        let topSpecular = UIView()
        topSpecular.isUserInteractionEnabled = false
        blurView.contentView.addSubview(topSpecular)
        topSpecular.snp.makeConstraints { $0.edges.equalToSuperview() }
        let topGrad = CAGradientLayer()
        topGrad.colors = [
            UIColor(white: 1, alpha: CGFloat(0x50) / 255).cgColor,
            UIColor(white: 1, alpha: CGFloat(0x10) / 255).cgColor,
            UIColor.clear.cgColor,
        ]
        topGrad.locations  = [0, 0.45, 1.0]
        topGrad.startPoint = CGPoint(x: 0.5, y: 0)
        topGrad.endPoint   = CGPoint(x: 0.5, y: 1)
        topSpecular.layer.addSublayer(topGrad)
        highlightLayers.append((topSpecular, topGrad))

        let bottomWarm = UIView()
        bottomWarm.isUserInteractionEnabled = false
        blurView.contentView.addSubview(bottomWarm)
        bottomWarm.snp.makeConstraints { $0.edges.equalToSuperview() }
        let bottomGrad = CAGradientLayer()
        bottomGrad.colors = [
            UIColor(hex: "#832C11", alpha: CGFloat(0x20) / 255).cgColor,
            UIColor(hex: "#832C11", alpha: CGFloat(0x0C) / 255).cgColor,
            UIColor.clear.cgColor,
        ]
        bottomGrad.locations  = [0, 0.5, 1.0]
        bottomGrad.startPoint = CGPoint(x: 0.5, y: 1)
        bottomGrad.endPoint   = CGPoint(x: 0.5, y: 0)
        bottomWarm.layer.addSublayer(bottomGrad)
        highlightLayers.append((bottomWarm, bottomGrad))

        button.backgroundColor = .clear
    }
    
    private func loadSentences() {
        viewWillAppearRelay.accept(())
    }

    // MARK: - Bindings

    private func bindActions() {
        backButton.rx.tap
            .subscribe(onNext: { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            })
            .disposed(by: disposeBag)

        fabButton.rx.tap
            .subscribe(onNext: { [weak self] in
                guard let self else { return }
                let cameraVC = CameraCollectionViewController()
                cameraVC.modalPresentationStyle = .fullScreen

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

                self.present(cameraVC, animated: true)
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
                vc.onPageRecorded = { [weak self] page in
                    guard let self, let itemPage = self.currentItemPage else { return }
                    self.latestCurrentPage = page
                    self.progressSectionView.configure(currentPage: page, itemPage: itemPage)
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
                guard let self, let itemPage = self.currentItemPage else { return }
                let vc = PageRecordViewController(itemPage: itemPage)
                vc.modalPresentationStyle = .pageSheet
                vc.onPageRecorded = { [weak self] page in
                    guard let self else { return }
                    self.latestCurrentPage = page
                    self.progressSectionView.configure(currentPage: page, itemPage: itemPage)
                    self.updateCurrentPageRelay.accept(page)
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
    }

}

// MARK: - Tutorial

extension BookDetailViewController {
    private func showTutorialIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "tutorial.bookDetail") else { return }

        let steps: [TutorialStep] = [
            TutorialStep(
                targetFrame: fabButton.convert(fabButton.bounds, to: nil),
                message: "카메라 OCR이나 직접 입력으로\n밑줄을 수집해보세요!"
            ),
            TutorialStep(
                targetFrame: quoteCard.convert(quoteCard.bounds, to: nil),
                message: "카드를 탭하면 앞뒷면이 뒤집혀요\n앞면은 문장, 뒷면은 메모예요"
            ),
            TutorialStep(
                targetFrame: timerButton.convert(timerButton.bounds, to: nil),
                message: "독서 시간을 기록하고\n통계를 확인하세요"
            ),
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
