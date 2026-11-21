import UIKit

@MainActor
enum TutorialSupport {
    static let keys = ["tutorial.bookshelf", "tutorial.bookDetail", "tutorial.readingRecord",
                       "tutorial.statistics", "tutorial.cardEditor", "tutorial.bookshelfWishlist",
                       "tutorial.searchWishlist", "tutorial.wishlist", "tutorial.purchaseSettings",
                       "tutorial.bookshelfDrag"]

    static func show(on controller: UIViewController, key: String, steps: [TutorialStep], completion: (() -> Void)? = nil) {
        guard controller.viewIfLoaded?.window != nil, controller.presentedViewController == nil,
              !UserDefaults.standard.bool(forKey: key), !steps.isEmpty else { return }
        let overlay = TutorialOverlayViewController()
        overlay.steps = steps
        overlay.modalPresentationStyle = .overFullScreen
        overlay.modalTransitionStyle = .crossDissolve
        overlay.onFinished = {
            UserDefaults.standard.set(true, forKey: key)
            completion?()
        }
        controller.present(overlay, animated: true)
    }

    static func viewStep(target: UIView, message: String) -> TutorialStep {
        TutorialStep(targetFrame: .zero, message: message, targetFrameProvider: { [weak target] in
            guard let target, target.window != nil else { return .zero }
            return target.convert(target.bounds, to: nil)
        })
    }

    static func barButtonStep(item: UIBarButtonItem, on controller: UIViewController, message: String) -> TutorialStep {
        TutorialStep(targetFrame: .zero, message: message, targetFrameProvider: { [weak item, weak controller] in
            guard let controller, let item, let window = controller.viewIfLoaded?.window else { return .zero }
            if let frame = item.frame(in: window), !frame.isEmpty, !frame.isNull {
                return frame
            }
            // 버튼이 overflow로 이동했다면 시스템 메뉴의 위치를 안내한다.
            return controller.navigationItem.overflowPresentationSource?.frame(in: window) ?? .zero
        })
    }

    static func target(in view: UIView, identifier: String) -> UIView? {
        if view.accessibilityIdentifier == identifier { return view }
        return view.subviews.lazy.compactMap { target(in: $0, identifier: identifier) }.first
    }
}
