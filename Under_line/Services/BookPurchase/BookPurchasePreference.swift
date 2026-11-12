import Foundation

enum BookPurchasePreference: Equatable {
    case askEveryTime
    case store(BookStore)

    var displayName: String {
        switch self {
        case .askEveryTime: return "구매할 때마다 선택"
        case .store(let store): return store.displayName
        }
    }
}

protocol BookPurchasePreferenceStoreProtocol {
    var current: BookPurchasePreference { get }
    func save(_ preference: BookPurchasePreference)
}

final class BookPurchasePreferenceStore: BookPurchasePreferenceStoreProtocol {
    private let defaults: UserDefaults
    private let key = "bookPurchase.preference"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var current: BookPurchasePreference {
        guard let raw = defaults.string(forKey: key), let store = BookStore(rawValue: raw) else {
            return .askEveryTime
        }
        return .store(store)
    }

    func save(_ preference: BookPurchasePreference) {
        switch preference {
        case .askEveryTime: defaults.set("askEveryTime", forKey: key)
        case .store(let store): defaults.set(store.rawValue, forKey: key)
        }
    }
}
