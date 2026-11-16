import UIKit
import SnapKit

@MainActor
enum SystemNavigationStyle {
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
    }

    static func button(image: String, label: String, identifier: String) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: image), for: .normal)
        button.tintColor = .appPrimary
        button.accessibilityLabel = label
        button.accessibilityIdentifier = identifier
        button.snp.makeConstraints { make in
            make.size.equalTo(44)
        }
        return button
    }

    static func item(image: String, label: String, identifier: String, tint: UIColor? = nil) -> UIBarButtonItem {
        let color = tint ?? .appPrimary
        let icon = UIImage(systemName: image)?.withTintColor(color, renderingMode: .alwaysOriginal)
        let item = UIBarButtonItem(image: icon, style: .plain, target: nil, action: nil)
        item.tintColor = tint ?? .appPrimary
        item.accessibilityLabel = label
        item.accessibilityIdentifier = identifier
        return item
    }
}
