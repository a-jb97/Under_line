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

    init(books: [Book?], isEditing: Bool = false, onDelete: ((Book) -> Void)? = nil, onTap: ((Book) -> Void)? = nil) {
        super.init(frame: .zero)
        setupBooks(books, isEditing: isEditing, onDelete: onDelete, onTap: onTap)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupBooks(_ books: [Book?], isEditing: Bool, onDelete: ((Book) -> Void)?, onTap: ((Book) -> Void)?) {
        let bookViews: [UIView] = books.map { makeBookView($0, isEditing: isEditing, onDelete: onDelete, onTap: onTap) }

        let booksStack = UIStackView(arrangedSubviews: bookViews)
        booksStack.axis      = .horizontal
        booksStack.spacing   = 20
        booksStack.alignment = .bottom

        bookViews.forEach { $0.snp.makeConstraints { make in
            make.width.equalTo(88)
            make.height.equalTo(117)
        }}

        addSubview(booksStack)

        booksStack.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview().inset(10)
            make.bottom.equalToSuperview().inset(22)  // 선반 보드 높이만큼 여백
        }
    }

    private func makeBookView(_ book: Book?, isEditing: Bool, onDelete: ((Book) -> Void)?, onTap: ((Book) -> Void)?) -> UIView {
        let wrapper = UIView()

        let container = UIView()
        container.layer.cornerRadius = 5
        container.clipsToBounds      = true
        wrapper.addSubview(container)
        container.snp.makeConstraints { $0.edges.equalToSuperview() }

        guard let book else {
            container.backgroundColor = .clear
            return wrapper
        }

        if let coverURL = book.coverURL {
            container.backgroundColor = UIColor.primary
            let iv = UIImageView()
            iv.contentMode = .scaleAspectFill
            iv.clipsToBounds = true
            iv.kf.setImage(with: coverURL)
            container.addSubview(iv)
            iv.snp.makeConstraints { $0.edges.equalToSuperview() }
        } else {
            container.backgroundColor = UIColor.primary
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

    init(rows: [RowData], isEditing: Bool = false, onDelete: ((Book) -> Void)? = nil, onTap: ((Book) -> Void)? = nil) {
        super.init(frame: .zero)
        setupRows(rows, isEditing: isEditing, onDelete: onDelete, onTap: onTap)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupRows(_ rows: [RowData], isEditing: Bool, onDelete: ((Book) -> Void)?, onTap: ((Book) -> Void)?) {
        let stack = UIStackView()
        stack.axis         = .vertical
        stack.distribution = .equalSpacing

        rows.forEach { rowData in
            stack.addArrangedSubview(ShelfRowView(books: rowData.books, isEditing: isEditing, onDelete: onDelete, onTap: onTap))
        }

        // 행 높이 합(top inset 10 + book 117 + shelf board 22) × 행 수
        // 스택 높이 = 0.5×pageHeight + rowsHeight/2 → 간격을 정확히 50% 축소
        let rowsHeight: CGFloat = (10 + 117 + 22) * CGFloat(rows.count)
        addSubview(stack)
        stack.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.centerY.equalToSuperview()
            make.height.equalToSuperview().multipliedBy(0.5).offset(rowsHeight / 2)
        }
    }
}
