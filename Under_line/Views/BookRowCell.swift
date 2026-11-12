import UIKit
import SnapKit
import RxSwift
import RxCocoa
import Kingfisher

// MARK: - BookRowCell

final class BookRowCell: UITableViewCell {

    static let reuseID = "BookRowCell"

    // MARK: - UI

    private let cardView: UIView = {
        let v = BookRowCardView()
        v.backgroundColor     = UIColor.background
        v.layer.cornerRadius  = 16
        v.layer.masksToBounds = false
        v.layer.shadowColor   = UIColor(hex: "#5d4037").cgColor
        v.layer.shadowOpacity = Float(CGFloat(0x30) / 255)
        v.layer.shadowRadius  = 4
        v.layer.shadowOffset  = CGSize(width: 4, height: 4)
        return v
    }()

    private let rankLabel: UILabel = {
        let l = UILabel()
        l.font          = UIFont(name: "GoyangIlsan L", size: 18) ?? .boldSystemFont(ofSize: 18)
        l.textColor     = UIColor(hex: "#190e0b")
        l.textAlignment = .center
        l.setContentHuggingPriority(.required, for: .horizontal)
        return l
    }()

    private let thumbnailImageView: UIImageView = {
        let iv = UIImageView()
        iv.backgroundColor    = UIColor.walnut
        iv.layer.cornerRadius = 3
        iv.clipsToBounds      = true
        iv.contentMode        = .scaleAspectFill
        return iv
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font          = UIFont(name: "GowunBatang-Regular", size: 16)
            ?? .systemFont(ofSize: 16, weight: .medium)
        l.textColor     = UIColor(hex: "#190e0b")
        l.numberOfLines = 2
        return l
    }()

    private let authorLabel: UILabel = {
        let l = UILabel()
        l.font      = UIFont(name: "GowunBatang-Regular", size: 13)
            ?? .systemFont(ofSize: 13)
        l.textColor = UIColor.walnut
        return l
    }()

    private let publisherLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont(name: "GowunBatang-Regular", size: 13)
            ?? .systemFont(ofSize: 13)
        label.textColor = UIColor.walnut
        return label
    }()

    private let registerButton: UIButton = {
        let btn = UIButton(type: .custom)
        btn.setImage(UIImage(systemName: "books.vertical"), for: .normal)
        btn.setImage(UIImage(systemName: "books.vertical.fill"), for: .selected)
        btn.setImage(UIImage(systemName: "books.vertical.fill"), for: [.selected, .disabled])
        btn.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 20), forImageIn: .normal)
        btn.tintColor = UIColor.walnut
        btn.accessibilityIdentifier = "registerBookButton"
        btn.accessibilityLabel = "독서 기록을 위한 도서 등록"
        btn.setContentHuggingPriority(.required, for: .horizontal)
        btn.setContentCompressionResistancePriority(.required, for: .horizontal)
        return btn
    }()

    private let wishlistButton: UIButton = {
        let button = UIButton(type: .custom)
        button.setImage(UIImage(systemName: "heart"), for: .normal)
        button.setImage(UIImage(systemName: "heart.fill"), for: .selected)
        button.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 20), forImageIn: .normal)
        button.tintColor = UIColor.walnut
        button.accessibilityIdentifier = "wishlistButton"
        button.accessibilityLabel = "위시리스트에 추가"
        button.isEnabled = false
        return button
    }()

    private let summaryView = UIView()

    private let descriptionContainer = UIView()

    private let descriptionTextView: UITextView = {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.font = UIFont(name: "GoyangIlsan R", size: 12) ?? .systemFont(ofSize: 12)
        textView.textColor = UIColor.appPrimary.withAlphaComponent(0.75)
        textView.isEditable = false
        textView.isSelectable = false
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = false
        textView.showsVerticalScrollIndicator = true
        textView.scrollsToTop = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        return textView
    }()

    private let descriptionLoadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.color = UIColor.walnut
        indicator.hidesWhenStopped = true
        return indicator
    }()

    #if DEBUG
    var performanceBatchID: UUID?
    #endif

    var onPrimaryAction: ((String) -> Void)?
    var onToggleWishlist: ((String) -> Void)?
    private var currentContent: BookRowContent?
    var isbn13: String? { currentContent?.isbn13 }
    private let disposeBag = DisposeBag()

    private var rankVisible = true
    private var rankedLeading: Constraint?
    private var unrankedLeading: Constraint?
    private var descriptionHeightConstraint: Constraint?
    private var descriptionMeasurementWidth: CGFloat = 0
    private var descriptionIsLoading = false
    private var lastDescriptionHeight: CGFloat = 0

    private var maximumDescriptionHeight: CGFloat {
        ceil((descriptionTextView.font?.lineHeight ?? 14) * 1.5 * 7)
    }

    private var loadingDescriptionHeight: CGFloat { 44 }

    // MARK: - Init

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupCell()
        registerButton.rx.tap
            .subscribe(onNext: { [weak self] in
                guard let self, self.registerButton.isEnabled, let content = self.currentContent else { return }
                self.onPrimaryAction?(content.isbn13)
            })
            .disposed(by: disposeBag)
        wishlistButton.rx.tap
            .subscribe(onNext: { [weak self] in
                guard let self, self.wishlistButton.isEnabled, let content = self.currentContent else { return }
                self.onToggleWishlist?(content.isbn13)
            })
            .disposed(by: disposeBag)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnailImageView.kf.cancelDownloadTask()
        // 취소할 DownloadTask가 없는 디스크 캐시 조회도 이전 요청으로 처리되도록 초기화한다.
        thumbnailImageView.kf.setImage(with: Optional<URL>.none)
        currentContent = nil
        setPrimaryAction(.registration(isRegistered: false))
        onPrimaryAction = nil
        onToggleWishlist = nil
        setWishlistAction(.wishlist(isSaved: false, isEnabled: false))
        rankLabel.text = nil
        titleLabel.text = nil
        authorLabel.text = nil
        publisherLabel.text = nil
        publisherLabel.isHidden = true
        descriptionTextView.attributedText = nil
        descriptionTextView.setContentOffset(.zero, animated: false)
        descriptionLoadingIndicator.stopAnimating()
        descriptionTextView.isHidden = false
        descriptionTextView.isScrollEnabled = false
        descriptionTextView.showsVerticalScrollIndicator = false
        descriptionContainer.isHidden = true
        descriptionMeasurementWidth = 0
        descriptionIsLoading = false
        lastDescriptionHeight = 0
        #if DEBUG
        performanceBatchID = nil
        #endif
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let measuredWidth = descriptionTextView.bounds.width
        if measuredWidth > 0,
           abs(measuredWidth - descriptionMeasurementWidth) > 0.5 {
            descriptionMeasurementWidth = measuredWidth
            updateDescriptionViewportHeight()
        }
    }

    // MARK: - Setup

    private func setupCell() {
        selectionStyle              = .none
        backgroundColor             = .clear
        contentView.backgroundColor = .clear
        contentView.clipsToBounds   = false

        contentView.addSubview(cardView)

        let contentStack = UIStackView(arrangedSubviews: [summaryView, descriptionContainer])
        contentStack.axis = .vertical
        cardView.addSubview(contentStack)

        let textStack = UIStackView(arrangedSubviews: [titleLabel, authorLabel, publisherLabel])
        textStack.axis    = .vertical
        textStack.spacing = 3

        let actionStack = UIStackView(arrangedSubviews: [registerButton, wishlistButton])
        actionStack.axis = .vertical
        actionStack.alignment = .center
        actionStack.spacing = 4

        [rankLabel, thumbnailImageView, textStack, actionStack].forEach {
            summaryView.addSubview($0)
        }
        descriptionContainer.addSubview(descriptionTextView)
        descriptionContainer.addSubview(descriptionLoadingIndicator)

        cardView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(6)
            make.bottom.equalToSuperview().inset(6)
            make.leading.trailing.equalToSuperview().inset(8)
            make.height.greaterThanOrEqualTo(80)
        }

        contentStack.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        summaryView.snp.makeConstraints { make in
            make.height.greaterThanOrEqualTo(80)
        }

        rankLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.centerY.equalToSuperview()
            make.width.equalTo(20)
        }

        thumbnailImageView.snp.prepareConstraints { make in
            unrankedLeading = make.leading.equalToSuperview().offset(16).constraint
        }
        thumbnailImageView.snp.makeConstraints { make in
            rankedLeading = make.leading.equalTo(rankLabel.snp.trailing).offset(14).constraint
            make.centerY.equalToSuperview()
            make.size.equalTo(BookCoverImageOptions.size)
        }

        textStack.snp.makeConstraints { make in
            make.leading.equalTo(thumbnailImageView.snp.trailing).offset(14)
            make.trailing.lessThanOrEqualTo(actionStack.snp.leading).offset(-14)
            make.centerY.equalToSuperview()
            make.top.greaterThanOrEqualToSuperview().offset(10)
            make.bottom.lessThanOrEqualToSuperview().inset(10)
        }

        actionStack.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(16)
            make.centerY.equalToSuperview()
            make.top.greaterThanOrEqualToSuperview().offset(10)
            make.bottom.lessThanOrEqualToSuperview().inset(10)
        }

        for button in [registerButton, wishlistButton] {
            button.snp.makeConstraints { make in
                make.width.height.greaterThanOrEqualTo(44)
            }
        }

        descriptionTextView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(4)
            make.leading.trailing.equalToSuperview().inset(16)
            make.bottom.equalToSuperview().inset(16)
            descriptionHeightConstraint = make.height
                .equalTo(maximumDescriptionHeight)
                .constraint
        }
        descriptionLoadingIndicator.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }

        descriptionContainer.isHidden = true
    }

    // MARK: - Configure

    func setPrimaryAction(_ action: BookRowAction) {
        apply(action, to: registerButton)
        registerButton.accessibilityIdentifier = action.symbolName == "cart" ? "purchaseBookButton" : "registerBookButton"
    }

    func setWishlistAction(_ action: BookRowAction) {
        apply(action, to: wishlistButton)
    }

    private func apply(_ action: BookRowAction, to button: UIButton) {
        let image = UIImage(systemName: action.symbolName)
        button.setImage(image, for: .normal)
        button.setImage(image, for: .selected)
        button.setImage(image, for: [.selected, .disabled])
        button.isSelected = action.isSelected
        button.isEnabled = currentContent != nil && action.isEnabled
        button.tintColor = action.isSelected ? UIColor.accent : UIColor.walnut
        button.accessibilityLabel = action.accessibilityLabel
        button.accessibilityValue = action.accessibilityValue
    }

    func configure(
        content: BookRowContent,
        displayScale: CGFloat,
        descriptionWidth: CGFloat,
        isExpanded: Bool,
        isDescriptionLoading: Bool,
        primaryAction: BookRowAction,
        wishlistAction: BookRowAction
    ) {
        thumbnailImageView.kf.cancelDownloadTask()
        let imageOptions = BookCoverImageOptions.make(displayScale: displayScale)
        currentContent = content
        setPrimaryAction(primaryAction)
        setWishlistAction(wishlistAction)
        rankLabel.text   = content.rank.map { "\($0)" }
        titleLabel.text  = content.title
        authorLabel.text = content.authorText
        let publisher = content.publisher.trimmingCharacters(in: .whitespacesAndNewlines)
        publisherLabel.text = publisher
        publisherLabel.isHidden = publisher.isEmpty

        let description = content.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = 1.5
        descriptionTextView.attributedText = NSAttributedString(
            string: description.isEmpty ? "책 소개가 없습니다" : description,
            attributes: [
                .font: descriptionTextView.font as Any,
                .foregroundColor: descriptionTextView.textColor as Any,
                .paragraphStyle: paragraphStyle,
            ]
        )
        descriptionMeasurementWidth = descriptionWidth
        lastDescriptionHeight = 0
        descriptionTextView.setContentOffset(.zero, animated: false)
        setExpanded(isExpanded)
        setDescriptionLoading(isExpanded && isDescriptionLoading)
        #if DEBUG
        let coverSpan = BookSearchPerformance.Span(.coverLoaded, source: .table, id: performanceBatchID ?? UUID())
        thumbnailImageView.kf.setImage(with: content.coverURL, options: imageOptions) { result in
            switch result {
            case .success(let value):
                let cache: BookSearchPerformance.Cache
                switch value.cacheType {
                case .none: cache = .none
                case .memory: cache = .memory
                case .disk: cache = .disk
                }
                coverSpan.finish(cache: cache)
            case .failure(let error):
                if content.coverURL == nil {
                    coverSpan.finish(.noURL)
                } else if error.isTaskCancelled {
                    coverSpan.finish(.cancelled)
                } else if error.isNotCurrentTask {
                    coverSpan.finish(.superseded)
                } else {
                    coverSpan.finish(.failed)
                }
            }
        }
        #else
        thumbnailImageView.kf.setImage(with: content.coverURL, options: imageOptions)
        #endif

        let showRank = content.rank != nil
        guard showRank != rankVisible else { return }
        rankVisible        = showRank
        rankLabel.isHidden = !showRank
        updateThumbnailLeading(showRank: showRank)
    }

    func setExpanded(_ isExpanded: Bool) {
        if !isExpanded {
            descriptionIsLoading = false
            descriptionLoadingIndicator.stopAnimating()
            descriptionTextView.isHidden = false
            updateDescriptionViewportHeight()
        }
        guard descriptionContainer.isHidden == isExpanded else { return }
        descriptionContainer.isHidden = !isExpanded
    }

    func setDescriptionLoading(_ isLoading: Bool) {
        descriptionIsLoading = isLoading
        descriptionTextView.isHidden = isLoading
        if isLoading {
            descriptionContainer.isHidden = false
            descriptionLoadingIndicator.startAnimating()
        } else {
            descriptionLoadingIndicator.stopAnimating()
        }
        updateDescriptionViewportHeight()
    }

    private func updateDescriptionViewportHeight() {
        let targetHeight: CGFloat
        let shouldScroll: Bool

        if descriptionIsLoading {
            targetHeight = loadingDescriptionHeight
            shouldScroll = false
        } else if descriptionMeasurementWidth > 0,
                  descriptionTextView.attributedText.length > 0 {
            descriptionTextView.isScrollEnabled = false
            let fittingSize = descriptionTextView.sizeThatFits(CGSize(
                width: descriptionMeasurementWidth,
                height: .greatestFiniteMagnitude
            ))
            let contentHeight = ceil(fittingSize.height)
            targetHeight = min(contentHeight, maximumDescriptionHeight)
            shouldScroll = contentHeight > maximumDescriptionHeight + 0.5
        } else {
            targetHeight = maximumDescriptionHeight
            shouldScroll = false
        }

        descriptionTextView.isScrollEnabled = shouldScroll
        descriptionTextView.showsVerticalScrollIndicator = shouldScroll
        guard abs(targetHeight - lastDescriptionHeight) > 0.5 else { return }
        lastDescriptionHeight = targetHeight
        descriptionHeightConstraint?.update(offset: targetHeight)
    }

    private func updateThumbnailLeading(showRank: Bool) {
        if showRank {
            unrankedLeading?.deactivate()
            rankedLeading?.activate()
        } else {
            rankedLeading?.deactivate()
            unrankedLeading?.activate()
        }
    }
}

// A self-sizing table cell can lay out before its card's final bounds are applied.
// Keep the shadow tied to the view whose geometry it describes.
private final class BookRowCardView: UIView {
    private var lastShadowBounds: CGRect = .null

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds != lastShadowBounds else { return }
        lastShadowBounds = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.shadowPath = bounds.isEmpty ? nil : UIBezierPath(
            roundedRect: bounds, cornerRadius: layer.cornerRadius
        ).cgPath
        CATransaction.commit()
    }
}
