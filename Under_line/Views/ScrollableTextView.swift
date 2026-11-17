import UIKit
import SnapKit

/// 짧은 본문은 세로 중앙에, 긴 본문은 끝까지 스크롤할 수 있게 표시한다.
final class ScrollableTextView: UIScrollView {
    init(label: UILabel) {
        super.init(frame: .zero)
        addSubview(label)
        label.snp.makeConstraints { make in
            make.edges.equalTo(contentLayoutGuide).inset(UIEdgeInsets(top: 12, left: 24, bottom: 12, right: 24))
            make.width.equalTo(frameLayoutGuide).offset(-48)
        }
        contentLayoutGuide.snp.makeConstraints { make in
            make.height.greaterThanOrEqualTo(frameLayoutGuide)
            make.height.equalTo(frameLayoutGuide).priority(.low)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
