//
//  AllSentenceCell.swift
//  Under_line
//
//  밑줄 모아보기 테이블뷰 셀 — 탭으로 확장/축소
//

import UIKit
import SnapKit

final class AllSentenceCell: UITableViewCell {

    static let reuseIdentifier = "AllSentenceCell"

    // MARK: - UI

    private let sentenceLabel: UILabel = {
        let l = UILabel()
        l.font = UIFont(name: "GowunBatang-Regular", size: 15) ?? .systemFont(ofSize: 15)
        l.textColor = .accent
        l.numberOfLines = 3
        l.lineBreakMode = .byTruncatingTail
        return l
    }()

    private let bookInfoLabel: UILabel = {
        let l = UILabel()
        l.font = UIFont(name: "GoyangIlsan R", size: 12) ?? .systemFont(ofSize: 12)
        l.textColor = UIColor.appPrimary.withAlphaComponent(0.6)
        l.numberOfLines = 0
        return l
    }()

    private let emotionImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        return iv
    }()

    private let emotionLabel: UILabel = {
        let l = UILabel()
        l.font = UIFont(name: "GoyangIlsan R", size: 13) ?? .systemFont(ofSize: 13)
        l.textColor = .appPrimary
        return l
    }()

    private let pageLabel: UILabel = {
        let l = UILabel()
        l.font = UIFont(name: "GoyangIlsan R", size: 13) ?? .systemFont(ofSize: 13)
        l.textColor = UIColor.appPrimary.withAlphaComponent(0.7)
        return l
    }()

    private let memoLabel: UILabel = {
        let l = UILabel()
        l.font = UIFont(name: "GoyangIlsan R", size: 13) ?? .systemFont(ofSize: 13)
        l.textColor = UIColor.accent.withAlphaComponent(0.5)
        l.numberOfLines = 0
        return l
    }()

    // 확장 시 표시 (UIStackView — isHidden 시 높이 0으로 자동 축소)
    private lazy var expandedStack: UIStackView = {
        let emotionRow = UIStackView(arrangedSubviews: [emotionImageView, emotionLabel, spacerView, pageLabel])
        emotionRow.axis = .horizontal
        emotionRow.spacing = 6
        emotionRow.alignment = .center
        emotionImageView.snp.makeConstraints { $0.size.equalTo(20) }

        let sv = UIStackView(arrangedSubviews: [emotionRow, memoLabel])
        sv.axis = .vertical
        sv.spacing = 8
        sv.isHidden = true
        return sv
    }()

    private let spacerView: UIView = {
        let v = UIView()
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return v
    }()

    // 전체 세로 스택 (hidden 뷰는 높이 0으로 자동 축소)
    private lazy var mainStack: UIStackView = {
        let sv = UIStackView(arrangedSubviews: [sentenceLabel, bookInfoLabel, expandedStack])
        sv.axis = .vertical
        sv.alignment = .fill
        sv.setCustomSpacing(6,  after: sentenceLabel)
        sv.setCustomSpacing(12, after: bookInfoLabel)
        return sv
    }()

    // MARK: - Init

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .background
        selectionStyle  = .none
        separatorInset  = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 0)

        contentView.addSubview(mainStack)
        mainStack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 16, left: 20, bottom: 16, right: 20))
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Configure

    func configure(with item: AllSentenceDisplayItem, isExpanded: Bool) {
        sentenceLabel.text = item.sentence.sentence
        bookInfoLabel.text = "\(item.bookTitle) · \(item.bookAuthor)"
        emotionImageView.image = item.sentence.emotion.emoji
        emotionLabel.text      = item.sentence.emotion.label
        pageLabel.text         = "p. \(item.sentence.page)"

        if let memo = item.sentence.memo, !memo.isEmpty {
            memoLabel.text     = "메모 : \(memo)"
            memoLabel.isHidden = false
        } else {
            memoLabel.text     = nil
            memoLabel.isHidden = true
        }

        // isExpanded를 직접 설정한 뒤 applyExpansionState 호출 (reuse 깜빡임 방지)
        self.isExpanded = isExpanded
        applyExpansionState()
    }

    // MARK: - Expand / Collapse

    var isExpanded: Bool = false

    private func applyExpansionState() {
        sentenceLabel.numberOfLines = isExpanded ? 0 : 3
        expandedStack.isHidden      = !isExpanded
    }
}
