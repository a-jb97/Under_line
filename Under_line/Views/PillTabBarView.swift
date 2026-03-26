//
//  PillTabBarView.swift
//  Under_line
//
//  커스텀 Pill 스타일 탭바
//

import UIKit
import SnapKit

// MARK: - PillTabBarView

final class PillTabBarView: UIView {

    enum Tab: Int, CaseIterable {
        case books, stats, settings

        var title: String {
            switch self {
            case .books:    return "도서"
            case .stats:    return "통계"
            case .settings: return "설정"
            }
        }

        var iconName: String {
            switch self {
            case .books:    return "house"
            case .stats:    return "chart.pie"
            case .settings: return "gearshape"
            }
        }
    }

    var selectedTab: Tab = .books {
        didSet { updateSelection() }
    }
    var onTabSelected: ((Tab) -> Void)?

    private let pill = UIView()
    private var tabViews: [TabItemView] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        backgroundColor = UIColor.background

        pill.backgroundColor = UIColor.background
        pill.layer.cornerRadius = 36
        pill.layer.borderWidth = 1
        pill.layer.borderColor = UIColor.primary.cgColor

        addSubview(pill)
        pill.snp.makeConstraints { make in
            make.top.equalToSuperview().inset(12)
            make.leading.trailing.equalToSuperview().inset(21)
            make.height.equalTo(62)
            make.bottom.equalTo(safeAreaLayoutGuide).inset(8)
        }

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually

        Tab.allCases.forEach { tab in
            let item = TabItemView(tab: tab)
            item.onTap = { [weak self] in
                self?.selectedTab = tab
                self?.onTabSelected?(tab)
            }
            tabViews.append(item)
            stack.addArrangedSubview(item)
        }

        pill.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(4)
        }

        updateSelection()
    }

    private func updateSelection() {
        tabViews.enumerated().forEach { index, view in
            view.isSelected = (index == selectedTab.rawValue)
        }
    }
}

// MARK: - TabItemView

private final class TabItemView: UIView {

    var isSelected: Bool = false { didSet { updateStyle() } }
    var onTap: (() -> Void)?

    private let icon = UIImageView()
    private let label = UILabel()
    private let tab: PillTabBarView.Tab

    init(tab: PillTabBarView.Tab) {
        self.tab = tab
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        layer.cornerRadius = 26

        icon.contentMode = .scaleAspectFit
        icon.image = UIImage(
            systemName: tab.iconName,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        )

        label.attributedText = NSAttributedString(
            string: tab.title,
            attributes: [
                .font: UIFont.systemFont(ofSize: 10, weight: .semibold),
                .kern: 0.5
            ]
        )

        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.axis = .vertical
        stack.spacing = 4
        stack.alignment = .center
        stack.isUserInteractionEnabled = false

        addSubview(stack)
        stack.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }

        icon.snp.makeConstraints { make in
            make.size.equalTo(18)
        }

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        updateStyle()
    }

    @objc private func tapped() { onTap?() }

    private func updateStyle() {
        if isSelected {
            backgroundColor = UIColor.primary
            icon.tintColor   = UIColor.background
            label.textColor  = UIColor.background
        } else {
            backgroundColor = .clear
            icon.tintColor   = UIColor.primary
            label.textColor  = UIColor.primary
        }
    }
}
