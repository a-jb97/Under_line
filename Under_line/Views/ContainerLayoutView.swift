import UIKit

/// 이후 화면별 배치에서 사용하는 크기·특성·예약 영역 변경 감지용 컨테이너.
final class ContainerLayoutView: UIView {
    private(set) var containerLayout: ContainerLayout?
    var onLayoutChange: ((ContainerLayout) -> Void)?
    /// 완전히 펼쳐도 접힘 영역의 공간을 유지할 화면에서만 사용한다.
    var reservesInactiveDivisions = false {
        didSet {
            if reservesInactiveDivisions != oldValue { setNeedsUpdateConstraints() }
        }
    }

    override var bounds: CGRect {
        didSet {
            if bounds != oldValue { setNeedsUpdateConstraints() }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        registerForTraitChanges([
            UITraitHorizontalSizeClass.self,
            UITraitVerticalSizeClass.self,
            UITraitDisplayScale.self
        ]) { (view: ContainerLayoutView, _: UITraitCollection) in
            view.setNeedsUpdateConstraints()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        setNeedsUpdateConstraints()
    }

    override func updateConstraints() {
        updateContainerLayout()
        super.updateConstraints()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Auto Layout으로 확정된 bounds도 반영한다.
        updateContainerLayout()
    }

    private func updateContainerLayout() {
        let layout = ContainerLayout(view: self, reservesInactiveDivisions: reservesInactiveDivisions)
        guard layout != containerLayout else { return }
        containerLayout = layout
        onLayoutChange?(layout)
    }
}
