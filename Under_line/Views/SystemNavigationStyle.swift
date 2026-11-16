import UIKit
import SnapKit

@MainActor
enum SystemNavigationStyle {
    enum ItemPriority {
        case standard
        case high
    }

    static func configure(_ controller: UIViewController, title: String, largeTitle: Bool = false) {
        controller.navigationItem.title = title
        controller.navigationItem.largeTitleDisplayMode = largeTitle ? .always : .never
        controller.navigationItem.backButtonDisplayMode = .minimal
        let backItem = UIBarButtonItem(title: "", style: .plain, target: nil, action: nil)
        backItem.tintColor = .appPrimary
        controller.navigationItem.backBarButtonItem = backItem
    }

    static func configure(_ navigationController: UINavigationController) {
        let bar = navigationController.navigationBar
        bar.prefersLargeTitles = true
        bar.tintColor = .appPrimary
        let appearance = UINavigationBarAppearance()
        appearance.titleTextAttributes = [
            .font: UIFont(name: "GowunBatang-Bold", size: 17) ?? .boldSystemFont(ofSize: 17),
            .foregroundColor: UIColor.accent
        ]
        appearance.largeTitleTextAttributes = [
            .font: UIFont(name: "GowunBatang-Bold", size: 34) ?? .boldSystemFont(ofSize: 34),
            .foregroundColor: UIColor.accent
        ]
        let backIndicator = UIImage(
            systemName: "chevron.backward",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        )
        appearance.setBackIndicatorImage(
            backIndicator?.withTintColor(.appPrimary, renderingMode: .alwaysOriginal),
            transitionMaskImage: backIndicator
        )
        bar.standardAppearance = appearance
        bar.compactAppearance = appearance
        bar.scrollEdgeAppearance = appearance
        bar.compactScrollEdgeAppearance = appearance
    }

    static func item(
        image: String,
        label: String,
        identifier: String,
        tint: UIColor? = nil,
        priority: ItemPriority = .standard
    ) -> UIBarButtonItem {
        let color = tint ?? .appPrimary
        let icon = UIImage(systemName: image)?.withTintColor(color, renderingMode: .alwaysOriginal)
        let item = UIBarButtonItem(title: label, image: icon, target: nil, action: nil, menu: nil)
        item.tintColor = color
        item.accessibilityLabel = label
        item.accessibilityIdentifier = identifier
        if #available(iOS 27.0, *) {
            item.visibilityPriority = priority == .high ? .high : .standard
        }
        // 배치 축은 시스템이 선택하며, 제목은 overflow 메뉴에서도 사용한다.
        return item
    }

    static func setTrailingItems(_ items: [UIBarButtonItem], on navigationItem: UINavigationItem) {
        // 각 액션을 독립 그룹으로 구성해 보조 액션부터 overflow로 이동할 수 있게 한다.
        navigationItem.trailingItemGroups = items.map { $0.creatingFixedGroup() }
    }

    static func usesVerticalBar(on controller: UIViewController) -> Bool {
        if #available(iOS 27.1, *) {
            return controller.traitCollection.verticalBarEdge != .unspecified
        }
        return false
    }

    static func observeBarPlacement(on controller: UIViewController) {
        if #available(iOS 27.1, *) {
            controller.registerForTraitChanges(UITraitCollection.systemTraitsAffectingVerticalBarEdge) {
                (controller: UIViewController, _: UITraitCollection) in
                controller.viewIfLoaded?.setNeedsLayout()
            }
        }
    }

    /// 가로 막대에서는 기존 왼쪽 제목을 유지하고, 세로 막대에서는 시스템 제목을 사용한다.
    static func setSectionTitle(_ title: String, leadingInset: CGFloat, on controller: UIViewController) {
        let item = controller.navigationItem
        if usesVerticalBar(on: controller) {
            guard item.title != title || item.leftBarButtonItem != nil else { return }
            item.leftBarButtonItem = nil
            item.title = title
        } else {
            let identifier = "sectionTitle.\(title)"
            guard item.leftBarButtonItem?.customView?.accessibilityIdentifier != identifier else { return }
            let label = UILabel()
            label.text = title
            label.font = UIFont(name: "GowunBatang-Bold", size: 26) ?? .systemFont(ofSize: 26, weight: .bold)
            label.textColor = .accent
            label.accessibilityTraits.insert(.header)
            let container = UIView()
            container.accessibilityIdentifier = identifier
            container.addSubview(label)
            label.snp.makeConstraints { make in
                make.leading.equalToSuperview().offset(leadingInset)
                make.top.bottom.trailing.equalToSuperview()
            }
            let titleItem = UIBarButtonItem(customView: container)
            if #available(iOS 26.0, *) {
                titleItem.hidesSharedBackground = true
            }
            item.title = ""
            item.leftBarButtonItem = titleItem
        }
    }
}
