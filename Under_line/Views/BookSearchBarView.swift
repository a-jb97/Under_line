import UIKit
import SnapKit

final class BookSearchBarView: UIView {
    let textField: UITextField = {
        let field = UITextField()
        let font = UIFont(name: "GoyangIlsan R", size: 14) ?? .systemFont(ofSize: 14)
        field.attributedPlaceholder = NSAttributedString(
            string: "책 제목 또는 저자를 검색하세요",
            attributes: [.font: font, .foregroundColor: UIColor(hex: "#190e0b").withAlphaComponent(0.5)]
        )
        field.font = font
        field.textColor = UIColor(hex: "#190e0b")
        field.backgroundColor = .clear
        field.returnKeyType = .search
        field.accessibilityLabel = "책 제목 또는 저자 검색"
        field.accessibilityIdentifier = "bookSearchField"
        return field
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.background
        layer.cornerRadius = 10
        layer.borderWidth = 1
        layer.borderColor = UIColor.walnut.cgColor
        let icon = UIImageView(image: UIImage(
            systemName: "magnifyingglass",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        ))
        icon.tintColor = UIColor.walnut
        icon.contentMode = .scaleAspectFit
        addSubview(icon)
        addSubview(textField)
        icon.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.centerY.equalToSuperview()
            make.size.equalTo(18)
        }
        textField.snp.makeConstraints { make in
            make.leading.equalTo(icon.snp.trailing).offset(10)
            make.trailing.equalToSuperview().inset(16)
            make.centerY.equalToSuperview()
        }
    }

    required init?(coder: NSCoder) { fatalError() }
}
