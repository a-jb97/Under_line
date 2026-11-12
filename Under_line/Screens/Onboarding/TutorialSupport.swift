import UIKit

@MainActor
enum TutorialSupport {
    static let keys = ["tutorial.bookshelf", "tutorial.bookDetail", "tutorial.readingRecord",
                       "tutorial.statistics", "tutorial.cardEditor", "tutorial.bookshelfWishlist",
                       "tutorial.searchWishlist", "tutorial.wishlist", "tutorial.purchaseSettings"]

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

    static func target(in view: UIView, identifier: String) -> UIView? {
        if view.accessibilityIdentifier == identifier { return view }
        return view.subviews.lazy.compactMap { target(in: $0, identifier: identifier) }.first
    }
}
