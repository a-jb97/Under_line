//
//  ShelfPageView.swift
//  Under_line
//
//  책장 한 페이지 (ShelfRowView × 3)
//

import UIKit
import SnapKit
import Kingfisher

// MARK: - ShelfRowView

/// 책 + 책장 보드 1행
final class ShelfRowView: UIView {

    init(books: [Book?], bookWidth: CGFloat = 88, isEditing: Bool = false, onDelete: ((Book) -> Void)? = nil, onTap: ((Book) -> Void)? = nil) {
        super.init(frame: .zero)
        setupBooks(books, bookWidth: bookWidth, isEditing: isEditing, onDelete: onDelete, onTap: onTap)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupBooks(_ books: [Book?], bookWidth: CGFloat, isEditing: Bool, onDelete: ((Book) -> Void)?, onTap: ((Book) -> Void)?) {
        let bookHeight: CGFloat = min(ceil(bookWidth * 117.0 / 88.0), 180.0)
        let bookViews: [UIView] = books.map { makeBookView($0, bookWidth: bookWidth, bookHeight: bookHeight, isEditing: isEditing, onDelete: onDelete, onTap: onTap) }

        let booksStack = UIStackView(arrangedSubviews: bookViews)
        booksStack.axis      = .horizontal
        booksStack.spacing   = 20
        booksStack.alignment = .bottom

        bookViews.forEach { $0.snp.makeConstraints { make in
            make.width.equalTo(bookWidth)
        }}

        addSubview(booksStack)

        booksStack.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview().offset(-2)
            make.bottom.equalToSuperview().inset(12)
        }
    }

    private func makeBookView(_ book: Book?, bookWidth: CGFloat, bookHeight: CGFloat, isEditing: Bool, onDelete: ((Book) -> Void)?, onTap: ((Book) -> Void)?) -> UIView {
        let wrapper = UIView()

        let container = UIView()
        container.layer.cornerRadius  = 3
        container.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        container.clipsToBounds       = true
        wrapper.addSubview(container)
        container.snp.makeConstraints { $0.edges.equalToSuperview() }

        guard let book else {
            container.backgroundColor = .clear
            wrapper.snp.makeConstraints { make in make.height.equalTo(bookHeight) }
            return wrapper
        }

        // 좌상단 광원 그림자 (wrapper는 clipsToBounds 없음)
        wrapper.layer.shadowColor   = UIColor.black.cgColor
        wrapper.layer.shadowOpacity = 0.28
        wrapper.layer.shadowRadius  = 5
        wrapper.layer.shadowOffset  = CGSize(width: 3, height: 4)
        wrapper.layer.cornerRadius   = 3
        wrapper.layer.maskedCorners  = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        wrapper.layer.shadowPath     = UIBezierPath(
            roundedRect: CGRect(origin: .zero, size: CGSize(width: bookWidth, height: bookHeight)),
            byRoundingCorners: [.topLeft, .topRight],
            cornerRadii: CGSize(width: 3, height: 3)
        ).cgPath

        wrapper.snp.makeConstraints { make in make.height.equalTo(bookHeight) }

        if let coverURL = book.coverURL {
            container.backgroundColor = UIColor.appPrimary
            let iv = UIImageView()
            iv.contentMode = .scaleAspectFill
            iv.clipsToBounds = true
            container.addSubview(iv)
            iv.snp.makeConstraints { $0.edges.equalToSuperview() }
            iv.kf.setImage(with: coverURL) { [weak wrapper] result in
                guard let wrapper, case .success(let value) = result else { return }
                let imageSize = value.image.size
                guard imageSize.width > 0 else { return }
                let rawHeight = ceil(bookWidth * imageSize.height / imageSize.width)
                let newHeight = min(rawHeight, 180.0)
                wrapper.snp.updateConstraints { make in
                    make.height.equalTo(newHeight)
                }
                wrapper.layer.shadowPath = UIBezierPath(
                    roundedRect: CGRect(origin: .zero, size: CGSize(width: bookWidth, height: newHeight)),
                    byRoundingCorners: [.topLeft, .topRight],
                    cornerRadii: CGSize(width: 3, height: 3)
                ).cgPath
                wrapper.superview?.setNeedsLayout()
            }
        } else {
            container.backgroundColor = UIColor.appPrimary
            let titleLabel = UILabel()
            titleLabel.text          = book.title
            titleLabel.font          = UIFont(name: "GowunBatang-Bold", size: 10) ?? .boldSystemFont(ofSize: 10)
            titleLabel.textColor     = UIColor.background
            titleLabel.textAlignment = .center
            titleLabel.numberOfLines = 4
            container.addSubview(titleLabel)
            titleLabel.snp.makeConstraints { make in
                make.top.equalToSuperview().inset(8)
                make.leading.trailing.equalToSuperview().inset(4)
            }
        }

        if isEditing {
            let deleteButton = UIButton(type: .system)
            deleteButton.backgroundColor = .systemRed
            deleteButton.layer.cornerRadius = 11
            deleteButton.clipsToBounds = true
            let cfg = UIImage.SymbolConfiguration(pointSize: 10, weight: .bold)
            deleteButton.setImage(UIImage(systemName: "minus", withConfiguration: cfg), for: .normal)
            deleteButton.tintColor = .white
            wrapper.addSubview(deleteButton)
            deleteButton.snp.makeConstraints { make in
                make.top.equalToSuperview().offset(-6)
                make.trailing.equalToSuperview().offset(6)
                make.size.equalTo(22)
            }
            deleteButton.addAction(UIAction { _ in onDelete?(book) }, for: .touchUpInside)
        } else {
            let tapButton = UIButton(type: .system)
            tapButton.backgroundColor = .clear
            wrapper.addSubview(tapButton)
            tapButton.snp.makeConstraints { $0.edges.equalToSuperview() }
            tapButton.addAction(UIAction { _ in onTap?(book) }, for: .touchUpInside)
        }

        return wrapper
    }
}

// MARK: - ShelfPageView

/// 책장 한 페이지 — 3행 수직 배치
final class ShelfPageView: UIView {

    struct RowData {
        let books: [Book?]
    }

    init(rows: [RowData], bookWidth: CGFloat = 88, isEditing: Bool = false, onDelete: ((Book) -> Void)? = nil, onTap: ((Book) -> Void)? = nil) {
        super.init(frame: .zero)
        setupRows(rows, bookWidth: bookWidth, isEditing: isEditing, onDelete: onDelete, onTap: onTap)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupRows(_ rows: [RowData], bookWidth: CGFloat, isEditing: Bool, onDelete: ((Book) -> Void)?, onTap: ((Book) -> Void)?) {
        let stack = UIStackView()
        stack.axis         = .vertical
        stack.distribution = .equalSpacing

        rows.forEach { rowData in
            stack.addArrangedSubview(ShelfRowView(books: rowData.books, bookWidth: bookWidth, isEditing: isEditing, onDelete: onDelete, onTap: onTap))
        }

        // 행 높이 합(top inset 10 + bookHeight + shelf board 22) × 행 수
        // 스택 높이 = 0.5×pageHeight + rowsHeight/2 → 간격을 정확히 50% 축소
        let bookHeight: CGFloat = min(ceil(bookWidth * 117.0 / 88.0), 180.0)
        let rowsHeight: CGFloat = (10 + bookHeight + 22) * CGFloat(rows.count)
        addSubview(stack)
        stack.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.centerY.equalToSuperview()
            make.height.equalToSuperview().multipliedBy(0.5).offset(rowsHeight / 2)
        }
    }
}
