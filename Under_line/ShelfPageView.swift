//
//  ShelfPageView.swift
//  Under_line
//
//  책장 한 페이지 (ShelfRowView × 3)
//

import UIKit
import SnapKit

// MARK: - BookCover

/// 책 커버 스타일 (디자인 토큰 기반)
enum BookCover {
    case dark           // $accent  #190e0b
    case medium         // $primary #5d4037
    case lightOutline   // $background + $primary border
    case lightDarkOutline // $background + $accent border

    var backgroundColor: UIColor {
        switch self {
        case .dark:             return UIColor.accent
        case .medium:           return UIColor.primary
        case .lightOutline:     return UIColor.background
        case .lightDarkOutline: return UIColor.background
        }
    }

    var borderColor: UIColor? {
        switch self {
        case .lightOutline:     return UIColor.primary
        case .lightDarkOutline: return UIColor.accent
        default:                return nil
        }
    }
}

// MARK: - ShelfRowView

/// 책 + 책장 보드 1행
final class ShelfRowView: UIView {

    init(books: [BookCover]) {
        super.init(frame: .zero)
        setupBooks(books)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupBooks(_ covers: [BookCover]) {
        // 책 뷰 생성
        let bookViews: [UIView] = covers.map { cover in
            let v = UIView()
            v.backgroundColor = cover.backgroundColor
            v.layer.cornerRadius = 5
            if let borderColor = cover.borderColor {
                v.layer.borderWidth = 1
                v.layer.borderColor = borderColor.cgColor
            }
            return v
        }

        // 책 수평 스택
        let booksStack = UIStackView(arrangedSubviews: bookViews)
        booksStack.axis = .horizontal
        booksStack.spacing = 20
        booksStack.alignment = .bottom

        bookViews.forEach { $0.snp.makeConstraints { make in
            make.width.equalTo(88)
            make.height.equalTo(117)
        }}

        addSubview(booksStack)

        booksStack.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview().inset(10)
            make.bottom.equalToSuperview().inset(22)  // 선반 보드 높이만큼 여백 (고정 오버레이로 대체)
        }
    }
}

// MARK: - ShelfPageView

/// 책장 한 페이지 — 3행 수직 배치
final class ShelfPageView: UIView {

    struct RowData {
        let books: [BookCover]
    }

    init(rows: [RowData]) {
        super.init(frame: .zero)
        setupRows(rows)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupRows(_ rows: [RowData]) {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.distribution = .equalSpacing

        rows.forEach { rowData in
            stack.addArrangedSubview(ShelfRowView(books: rowData.books))
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
