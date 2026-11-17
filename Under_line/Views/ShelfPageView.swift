import UIKit
import SnapKit
import RxSwift
import RxCocoa
import Kingfisher

/// 전달받은 도서를 계산된 슬롯에 배치하는 한 페이지.
final class ShelfPageView: UIView {
    private var bookViews: [Int: UIView] = [:]

    init(books: [Book], layout: BookshelfLayout, page: Int, hiddenBookIndex: Int?, isEditing: Bool,
         onDelete: @escaping (Book) -> Void, onTap: @escaping (Book) -> Void) {
        super.init(frame: .zero)
        for (slotIndex, frame) in layout.slots.enumerated() {
            let index = page * layout.capacity + slotIndex
            guard books.indices.contains(index), index != hiddenBookIndex else { continue }
            let bookView = ShelfBookView(frame: frame)
            bookView.configure(book: books[index], slotSize: frame.size, isEditing: isEditing,
                               onDelete: onDelete, onTap: onTap)
            addSubview(bookView)
            bookViews[index] = bookView
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func bookView(at index: Int) -> UIView? { bookViews[index] }
}

private final class ShelfBookView: UIView {
    private let coverContainer = UIView()
    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    private let tapButton = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)
    private var disposeBag = DisposeBag()
    private var slotSize = CGSize.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(coverContainer)
        coverContainer.backgroundColor = .appPrimary
        coverContainer.layer.cornerRadius = 3
        coverContainer.layer.shadowColor = UIColor.black.cgColor
        coverContainer.layer.shadowOpacity = 0.28
        coverContainer.layer.shadowRadius = 5
        coverContainer.layer.shadowOffset = CGSize(width: 3, height: 4)
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 3
        coverContainer.addSubview(imageView)
        imageView.snp.makeConstraints { $0.edges.equalToSuperview() }
        titleLabel.font = UIFont(name: "GowunBatang-Bold", size: 10) ?? .boldSystemFont(ofSize: 10)
        titleLabel.textColor = .background
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 4
        coverContainer.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().inset(8)
            make.leading.trailing.equalToSuperview().inset(4)
            make.bottom.lessThanOrEqualToSuperview().inset(4)
        }
        coverContainer.snp.makeConstraints { make in
            make.centerX.bottom.equalToSuperview()
            make.width.height.equalTo(0)
        }
        addSubview(tapButton)
        tapButton.snp.makeConstraints { $0.edges.equalTo(coverContainer) }
        deleteButton.backgroundColor = .systemRed
        deleteButton.layer.cornerRadius = 11
        deleteButton.tintColor = .white
        deleteButton.setImage(UIImage(systemName: "minus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .bold)), for: .normal)
        addSubview(deleteButton)
        deleteButton.snp.makeConstraints { make in
            make.top.equalTo(coverContainer).offset(-6)
            make.trailing.equalTo(coverContainer).offset(6)
            make.size.equalTo(22)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(book: Book, slotSize: CGSize, isEditing: Bool,
                   onDelete: @escaping (Book) -> Void, onTap: @escaping (Book) -> Void) {
        disposeBag = DisposeBag()
        imageView.kf.cancelDownloadTask()
        imageView.image = nil
        self.slotSize = slotSize
        titleLabel.text = book.displayTitle
        titleLabel.isHidden = false
        fitCover(imageSize: CGSize(width: 88, height: 117))
        tapButton.isHidden = isEditing
        deleteButton.isHidden = !isEditing
        tapButton.accessibilityLabel = book.title
        tapButton.accessibilityIdentifier = "shelfBook.\(book.isbn13)"
        deleteButton.accessibilityLabel = "\(book.title) 꺼내기"
        deleteButton.accessibilityIdentifier = "deleteShelfBook.\(book.isbn13)"
        tapButton.rx.tap.subscribe(onNext: { onTap(book) }).disposed(by: disposeBag)
        deleteButton.rx.tap.subscribe(onNext: { onDelete(book) }).disposed(by: disposeBag)
        if let url = book.coverURL {
            imageView.kf.setImage(with: url) { [weak self] result in
                guard let self, case .success(let value) = result else { return }
                self.titleLabel.isHidden = true
                self.fitCover(imageSize: value.image.size)
            }
        }
    }

    private func fitCover(imageSize: CGSize) {
        guard imageSize.width > 0, imageSize.height > 0 else { return }
        let scale = min(slotSize.width / imageSize.width, slotSize.height / imageSize.height)
        let size = CGSize(width: floor(imageSize.width * scale), height: floor(imageSize.height * scale))
        coverContainer.snp.updateConstraints { make in
            make.width.equalTo(size.width)
            make.height.equalTo(size.height)
        }
        coverContainer.layer.shadowPath = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 3).cgPath
    }
}
