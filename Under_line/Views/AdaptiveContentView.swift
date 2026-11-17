import UIKit
import SnapKit

/// 화면 상태나 뷰를 재생성하지 않고 콘텐츠 제약의 기준 영역만 갱신한다.
final class AdaptiveContentView: UIView {
    let contentLayoutGuide = UILayoutGuide()
    private let avoidsKeyboard: Bool
    private var lastFrame: CGRect?

    init(avoidsKeyboard: Bool = false) {
        self.avoidsKeyboard = avoidsKeyboard
        super.init(frame: .zero)
        addLayoutGuide(contentLayoutGuide)
        contentLayoutGuide.snp.makeConstraints { make in
            make.left.top.equalToSuperview()
            make.width.height.equalTo(0)
        }
        registerForTraitChanges([UITraitHorizontalSizeClass.self, UITraitVerticalSizeClass.self]) {
            (view: AdaptiveContentView, _: UITraitCollection) in view.setNeedsUpdateConstraints()
        }
        if avoidsKeyboard {
            NotificationCenter.default.addObserver(self, selector: #selector(keyboardDidChange),
                                                   name: UIResponder.keyboardDidChangeFrameNotification, object: nil)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { NotificationCenter.default.removeObserver(self) }

    override var bounds: CGRect {
        didSet { if bounds != oldValue { setNeedsUpdateConstraints() } }
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        setNeedsUpdateConstraints()
    }

    @objc private func keyboardDidChange() { setNeedsUpdateConstraints() }

    override func updateConstraints() {
        updateContentFrame()
        super.updateConstraints()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateContentFrame()
    }

    private func updateContentFrame() {
        let keyboard = keyboardLayoutGuide.layoutFrame
        let keyboardTop = avoidsKeyboard && keyboard.height > safeAreaInsets.bottom && keyboard.width > 0
            ? keyboard.minY : nil
        let frame = ReadableContentLayout(container: ContainerLayout(view: self), keyboardTop: keyboardTop).frame
        guard frame != lastFrame else { return }
        lastFrame = frame
        contentLayoutGuide.snp.remakeConstraints { make in
            make.left.equalToSuperview().offset(frame.minX)
            make.top.equalToSuperview().offset(frame.minY)
            make.width.equalTo(frame.width)
            make.height.equalTo(frame.height)
        }
    }
}

extension UIView {
    var adaptiveContentLayoutGuide: UILayoutGuide {
        (self as? AdaptiveContentView)?.contentLayoutGuide ?? safeAreaLayoutGuide
    }
}

class AdaptiveViewController: UIViewController {
    var avoidsKeyboard: Bool { false }
    private var lastContentFrame: CGRect?
    private var scrollPositions: [ScrollPosition] = []

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        scrollPositions = scrollViews(in: view).map(ScrollPosition.init)
    }

    override func loadView() {
        view = AdaptiveContentView(avoidsKeyboard: avoidsKeyboard)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let frame = view.adaptiveContentLayoutGuide.layoutFrame
        guard frame != lastContentFrame else { return }
        lastContentFrame = frame
        scrollPositions.forEach { $0.restore() }
        guard avoidsKeyboard, let responder = firstResponder(in: view) else { return }
        var ancestor = responder.superview
        while let current = ancestor {
            if let scroll = current as? UIScrollView {
                scroll.scrollRectToVisible(responder.convert(responder.bounds, to: scroll).insetBy(dx: 0, dy: -12), animated: false)
                break
            }
            ancestor = current.superview
        }
    }

    private func firstResponder(in parent: UIView) -> UIView? {
        if parent.isFirstResponder { return parent }
        return parent.subviews.lazy.compactMap { self.firstResponder(in: $0) }.first
    }

    private func scrollViews(in parent: UIView) -> [UIScrollView] {
        parent.subviews.flatMap { child -> [UIScrollView] in
            if let scroll = child as? UIScrollView, !(child is UITextView) { return [scroll] }
            return scrollViews(in: child)
        }
    }
}

private struct ScrollPosition {
    let view: UIScrollView
    let offset: CGPoint
    let page: CGFloat?
    let row: IndexPath?
    let rowOffset: CGFloat

    init(_ view: UIScrollView) {
        self.view = view
        offset = view.contentOffset
        page = view.isPagingEnabled && view.bounds.width > 0 ? round(offset.x / view.bounds.width) : nil
        let table = view as? UITableView
        row = table?.indexPathsForVisibleRows?.min()
        if let table, let row { rowOffset = table.rectForRow(at: row).minY - offset.y }
        else { rowOffset = 0 }
    }

    func restore() {
        var target = offset
        if let page { target.x = page * view.bounds.width }
        if let table = view as? UITableView, let row,
           row.section < table.numberOfSections, row.row < table.numberOfRows(inSection: row.section) {
            target.y = table.rectForRow(at: row).minY - rowOffset
        }
        let inset = view.adjustedContentInset
        target.x = min(max(-inset.left, view.contentSize.width - view.bounds.width + inset.right), max(-inset.left, target.x))
        target.y = min(max(-inset.top, view.contentSize.height - view.bounds.height + inset.bottom), max(-inset.top, target.y))
        view.setContentOffset(target, animated: false)
    }
}

final class ScrollableFormView: UIScrollView {
    let formContentView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        keyboardDismissMode = .interactive
        alwaysBounceVertical = true
        addSubview(formContentView)
        formContentView.snp.makeConstraints { make in
            make.edges.equalTo(contentLayoutGuide)
            make.width.equalTo(frameLayoutGuide)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
