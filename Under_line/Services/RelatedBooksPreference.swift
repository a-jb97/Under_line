import Foundation
import RxSwift
import RxCocoa

@MainActor
final class RelatedBooksPreference {
    private let defaults: UserDefaults
    private let key = "relatedBooks.isEnabled"
    private let enabled: BehaviorRelay<Bool>

    var changes: Observable<Bool> { enabled.distinctUntilChanged() }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = BehaviorRelay(value: defaults.object(forKey: key) as? Bool ?? true)
    }

    func setEnabled(_ value: Bool) {
        defaults.set(value, forKey: key)
        enabled.accept(value)
    }
}
