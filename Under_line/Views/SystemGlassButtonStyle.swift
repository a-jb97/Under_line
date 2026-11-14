import UIKit

@MainActor
enum SystemGlassButtonStyle {
    // Glass의 자동 전경색 대신 아이콘 자체에 앱 색상을 적용한다.
    static func icon(_ image: UIImage?) -> UIImage? {
        image?.withTintColor(.appPrimary, renderingMode: .alwaysOriginal)
    }

    static func apply(to button: UIButton, accessibilityLabel: String) {
        let previous = button.configuration
        let image = previous?.image ?? button.image(for: .normal)
        let title = previous?.title ?? button.title(for: .normal)
        let attributedTitle = previous?.attributedTitle
        let foreground = previous?.baseForegroundColor
            ?? (image == nil ? button.titleColor(for: .normal) : button.tintColor)
        let font = button.titleLabel?.font ?? .systemFont(ofSize: 14, weight: .semibold)

        var configuration: UIButton.Configuration
        if #available(iOS 26.0, *) {
            configuration = .glass()
        } else {
            configuration = .gray()
        }
        configuration.cornerStyle = .capsule
        configuration.image = icon(image)
        configuration.imageColorTransformer = UIConfigurationColorTransformer { _ in .appPrimary }
        configuration.title = title
        configuration.attributedTitle = attributedTitle
        configuration.baseForegroundColor = foreground
        configuration.imagePlacement = previous?.imagePlacement ?? .leading
        configuration.imagePadding = previous?.imagePadding ?? 0
        configuration.contentInsets = title == nil && attributedTitle == nil
            ? .zero
            : NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        if let transformer = previous?.titleTextAttributesTransformer {
            configuration.titleTextAttributesTransformer = transformer
        } else if attributedTitle == nil {
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var attributes = attributes
                attributes.font = font
                return attributes
            }
        }

        button.setImage(nil, for: .normal)
        button.setTitle(nil, for: .normal)
        button.backgroundColor = .clear
        button.layer.cornerRadius = 0
        button.clipsToBounds = false
        button.tintColor = .appPrimary
        button.configuration = configuration
        button.accessibilityLabel = accessibilityLabel
    }

    static func setEditing(_ editing: Bool, on button: UIButton, accessibilityLabel: String) {
        var configuration = button.configuration
        configuration?.image = editing ? nil : icon(UIImage(
            systemName: "square.and.pencil",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        ))
        configuration?.title = editing ? "완료" : nil
        configuration?.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = .systemFont(ofSize: 14, weight: .semibold)
            return attributes
        }
        button.configuration = configuration
        button.accessibilityLabel = editing ? "편집 완료" : accessibilityLabel
    }
}
