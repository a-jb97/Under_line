import Kingfisher
import RxCocoa
import RxSwift
import SnapKit
import UIKit

final class BookDetailInfoView: UIView {
    private let coverWidth: CGFloat = 60
    private let defaultCoverRatio: CGFloat = 83.0 / 60
    private let coverView: UIImageView = {
        let view = UIImageView()
        view.backgroundColor = .appPrimary
        view.layer.cornerRadius = 3
        view.clipsToBounds = true
        view.contentMode = .scaleAspectFill
        for axis in [NSLayoutConstraint.Axis.horizontal, .vertical] {
            view.setContentHuggingPriority(.fittingSizeLevel, for: axis)
            view.setContentCompressionResistancePriority(.fittingSizeLevel, for: axis)
        }
        return view
    }()

    private let titleLabel = UILabel()
    private let authorLabel = UILabel()
    private let publisherLabel = UILabel()
    private let genreTag = UIView()
    private let genreLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let moreButton = UIButton(type: .system)
    private let header = UIView()
    private let disposeBag = DisposeBag()
    private var collapsedBottom: Constraint?
    private var expandedBottom: Constraint?
    private var coverURL: URL?
    private var isbn: String?

    var onHeightChange: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        titleLabel.font = UIFont(name: "GowunBatang-Bold", size: 17) ?? .systemFont(ofSize: 17, weight: .bold)
        titleLabel.textColor = .accent
        authorLabel.font = UIFont(name: "GowunBatang-Regular", size: 13) ?? .systemFont(ofSize: 13)
        authorLabel.textColor = .appPrimary
        publisherLabel.font = UIFont(name: "GoyangIlsan R", size: 11) ?? .systemFont(ofSize: 11)
        publisherLabel.textColor = .appPrimary.withAlphaComponent(0.5)
        genreTag.backgroundColor = .appPrimary.withAlphaComponent(0.7)
        genreTag.layer.cornerRadius = 3
        genreLabel.font = UIFont(name: "GoyangIlsan R", size: 10) ?? .systemFont(ofSize: 10)
        genreLabel.textColor = .white
        moreButton.setTitle("더 보기", for: .normal)
        moreButton.titleLabel?.font = UIFont(name: "GoyangIlsan R", size: 11) ?? .systemFont(ofSize: 11)
        moreButton.setTitleColor(.appPrimary.withAlphaComponent(0.7), for: .normal)
        moreButton.contentHorizontalAlignment = .right
        moreButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        moreButton.isHidden = true
        descriptionLabel.numberOfLines = 0
        descriptionLabel.isHidden = true

        addSubview(header)
        addSubview(descriptionLabel)
        [coverView, titleLabel, authorLabel, publisherLabel, genreTag, moreButton].forEach(header.addSubview)
        genreTag.addSubview(genreLabel)

        header.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            collapsedBottom = make.bottom.equalToSuperview().constraint
        }
        descriptionLabel.snp.makeConstraints { make in
            make.top.equalTo(header.snp.bottom).offset(10)
            make.leading.trailing.equalToSuperview()
        }
        expandedBottom = descriptionLabel.snp.prepareConstraints { make in
            make.bottom.equalToSuperview()
        }.first
        titleLabel.snp.makeConstraints { make in
            make.top.trailing.equalToSuperview()
            make.leading.equalToSuperview().offset(coverWidth + 14)
        }
        authorLabel.snp.makeConstraints { make in
            make.leading.trailing.equalTo(titleLabel)
            make.top.equalTo(titleLabel.snp.bottom).offset(4)
        }
        publisherLabel.snp.makeConstraints { make in
            make.leading.trailing.equalTo(titleLabel)
            make.top.equalTo(authorLabel.snp.bottom).offset(4)
        }
        genreTag.snp.makeConstraints { make in
            make.leading.equalTo(titleLabel)
            make.trailing.lessThanOrEqualTo(moreButton.snp.leading).offset(-4)
            make.top.equalTo(publisherLabel.snp.bottom).offset(6)
            make.bottom.equalToSuperview()
        }
        genreLabel.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 2, left: 8, bottom: 2, right: 8))
        }
        moreButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview()
            make.centerY.equalTo(genreTag)
        }
        updateCoverConstraints(ratio: defaultCoverRatio)

        moreButton.rx.tap
            .subscribe(onNext: { [weak self] in
                guard let self else { return }
                self.setDescriptionExpanded(self.descriptionLabel.isHidden)
                self.onHeightChange?()
            })
            .disposed(by: disposeBag)
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(with book: Book) {
        if isbn != book.isbn13 || book.description.isEmpty {
            setDescriptionExpanded(false)
        }
        isbn = book.isbn13
        titleLabel.text = book.displayTitle
        authorLabel.text = book.author
        publisherLabel.text = [book.publisher, book.publishDate ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
        genreLabel.text = BookGenre.normalized(book.category)
        moreButton.isHidden = book.description.isEmpty

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = 1.5
        descriptionLabel.attributedText = NSAttributedString(string: book.description, attributes: [
            .font: UIFont(name: "GoyangIlsan R", size: 12) ?? .systemFont(ofSize: 12),
            .foregroundColor: UIColor.appPrimary.withAlphaComponent(0.75),
            .paragraphStyle: paragraphStyle
        ])

        guard coverURL != book.coverURL else { return }
        coverURL = book.coverURL
        coverView.kf.cancelDownloadTask()
        coverView.image = nil
        updateCoverConstraints(ratio: defaultCoverRatio)
        guard let url = book.coverURL else { return }
        let request = ShelfCoverImageSource.request(for: url)
        coverView.kf.setImage(with: request.url, options: request.options) { [weak self] result in
            guard let self, self.coverURL == url, case .success(let value) = result else { return }
            let size = value.image.size
            guard size.width > 0, size.height > 0 else { return }
            self.updateCoverConstraints(ratio: size.height / size.width)
            self.onHeightChange?()
        }
    }

    private func setDescriptionExpanded(_ expanded: Bool) {
        guard expanded == descriptionLabel.isHidden else { return }
        if expanded {
            collapsedBottom?.deactivate()
            expandedBottom?.activate()
        } else {
            expandedBottom?.deactivate()
            collapsedBottom?.activate()
        }
        descriptionLabel.isHidden = !expanded
        moreButton.setTitle(expanded ? "가리기" : "더 보기", for: .normal)
    }

    private func updateCoverConstraints(ratio: CGFloat) {
        coverView.snp.remakeConstraints { make in
            make.leading.equalToSuperview()
            make.top.greaterThanOrEqualToSuperview()
            make.bottom.equalTo(genreTag)
            make.width.lessThanOrEqualTo(coverWidth)
            make.width.equalTo(coverWidth).priority(249)
            make.height.equalTo(coverView.snp.width).multipliedBy(ratio)
        }
    }
}
