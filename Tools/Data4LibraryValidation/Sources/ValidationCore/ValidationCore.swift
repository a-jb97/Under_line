import Foundation

public struct ValidationBook: Codable, Sendable {
    public let id: String
    public let titleQuery: String
    public let expectedTitle: String
    public let authorQuery: String
    public let expectedAuthors: [String]
    public let isbn13: String
    public let publisher: String
    public let publicationDate: String
    public let category: String
    public let recency: String
    public let tags: [String]
    public let selectionSource: String
}

public struct CoverObservation: Codable, Sendable {
    public let urlPresent: Bool
    public let loaded: Bool
    public let statusCode: Int?
    public let mimeType: String?
    public let byteCount: Int?
    public let pixelWidth: Int?
    public let pixelHeight: Int?
    public let meetsResolution: Bool
    public let contentHash: String?
    public let elapsedMilliseconds: Double?
    public let error: String?

    public init(
        urlPresent: Bool,
        loaded: Bool,
        statusCode: Int?,
        mimeType: String?,
        byteCount: Int?,
        pixelWidth: Int?,
        pixelHeight: Int?,
        meetsResolution: Bool,
        contentHash: String?,
        elapsedMilliseconds: Double?,
        error: String?
    ) {
        self.urlPresent = urlPresent
        self.loaded = loaded
        self.statusCode = statusCode
        self.mimeType = mimeType
        self.byteCount = byteCount
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.meetsResolution = meetsResolution
        self.contentHash = contentHash
        self.elapsedMilliseconds = elapsedMilliseconds
        self.error = error
    }
}

public struct RateSummary: Sendable {
    public let successes: Int
    public let total: Int

    public init(successes: Int, total: Int) {
        self.successes = successes
        self.total = total
    }

    public var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(successes) / Double(total) * 100
    }
}

public enum ISBN13Validator {
    public static func isValid(_ rawValue: String) -> Bool {
        let digits = rawValue.compactMap(\.wholeNumberValue)
        guard digits.count == 13, rawValue.count == 13 else { return false }
        let sum = digits.dropLast().enumerated().reduce(0) { partial, pair in
            partial + pair.element * (pair.offset.isMultiple(of: 2) ? 1 : 3)
        }
        return (10 - sum % 10) % 10 == digits.last
    }
}

public func validationAverage(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    return values.reduce(0, +) / Double(values.count)
}

public func validationMedian(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    let middle = sorted.count / 2
    if sorted.count.isMultiple(of: 2) {
        return (sorted[middle - 1] + sorted[middle]) / 2
    }
    return sorted[middle]
}

public func validationPercentile(_ values: [Double], _ quantile: Double) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    let rank = max(1, Int(ceil(Double(sorted.count) * min(max(quantile, 0), 1))))
    return sorted[min(rank - 1, sorted.count - 1)]
}

public func normalizedISBN13(_ value: String?) -> String? {
    guard let value else { return nil }
    let digits = value.filter(\.isNumber)
    return digits.count == 13 ? digits : nil
}

public func normalizedBookText(_ value: String?) -> String {
    guard let value else { return "" }
    return value.lowercased().unicodeScalars
        .filter { CharacterSet.alphanumerics.contains($0) }
        .map(String.init)
        .joined()
}
