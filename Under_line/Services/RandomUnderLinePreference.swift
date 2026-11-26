import Foundation

struct RandomUnderLinePreference {
    private let defaults: UserDefaults
    private let disabledKey = "randomUnderLine.isDisabled"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isEnabled: Bool { !defaults.bool(forKey: disabledKey) }

    func setEnabled(_ isEnabled: Bool) {
        defaults.set(!isEnabled, forKey: disabledKey)
    }
}
