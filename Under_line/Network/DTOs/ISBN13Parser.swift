import Foundation

enum ISBN13Parser {
    nonisolated static func isbn13(in rawValue: String) -> String? {
        rawValue
            .split(whereSeparator: { $0.isWhitespace })
            .map { $0.filter(\.isNumber) }
            .first(where: isValidISBN13)
    }

    nonisolated static func isValidISBN13(_ value: String) -> Bool {
        let digits = value.compactMap(\.wholeNumberValue)
        guard value.count == 13, digits.count == 13 else { return false }
        let sum = digits.dropLast().enumerated().reduce(0) { partial, pair in
            partial + pair.element * (pair.offset.isMultiple(of: 2) ? 1 : 3)
        }
        return (10 - sum % 10) % 10 == digits.last
    }
}
