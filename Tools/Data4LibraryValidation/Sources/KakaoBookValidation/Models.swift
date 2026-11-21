import Foundation
import ValidationCore

enum KakaoSearchKind: String, Codable, Sendable {
    case title
    case author
    case isbn
}

enum KakaoSearchMode: String, Codable, Sendable {
    case general
    case targeted
}

struct KakaoBookResponse: Decodable, Sendable {
    let meta: KakaoMeta
    let documents: [KakaoDocument]
}

struct KakaoMeta: Decodable, Sendable {
    let totalCount: Int
    let pageableCount: Int
    let isEnd: Bool

    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case pageableCount = "pageable_count"
        case isEnd = "is_end"
    }
}

struct KakaoDocument: Codable, Sendable {
    let title: String
    let contents: String
    let url: String
    let isbn: String
    let datetime: String
    let authors: [String]
    let publisher: String
    let translators: [String]
    let price: Int
    let salePrice: Int
    let thumbnail: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case title, contents, url, isbn, datetime, authors, publisher, translators, price, thumbnail, status
        case salePrice = "sale_price"
    }
}

enum KakaoISBN {
    static func tokens(in rawValue: String) -> [String] {
        rawValue.split(whereSeparator: { $0.isWhitespace })
            .map { $0.filter { $0.isNumber || $0 == "X" || $0 == "x" }.uppercased() }
            .filter { $0.count == 10 || $0.count == 13 }
    }

    static func isbn13s(in rawValue: String) -> [String] {
        tokens(in: rawValue).filter { $0.count == 13 }
    }

    static func contains(_ expectedISBN13: String, in rawValue: String) -> Bool {
        isbn13s(in: rawValue).contains(expectedISBN13)
    }
}

struct KakaoTimedSearchResult: Sendable {
    let documents: [KakaoDocument]
    let totalCount: Int
    let pageableCount: Int
    let cumulativeMilliseconds: Double
    let firstPageMilliseconds: Double
    let pageTimingsMilliseconds: [Double]
}

struct KakaoSearchObservation: Codable, Sendable {
    let kind: KakaoSearchKind
    let mode: KakaoSearchMode
    let target: String?
    let targetRank: Int?
    let resultCount: Int
    let totalCount: Int?
    let pageableCount: Int?
    let cumulativeTimingsMilliseconds: [Double]
    let firstPageTimingsMilliseconds: [Double]
    let pageTimingsMilliseconds: [[Double]]
    let repetitionMatches: [Bool]
    let otherEditionOnly: Bool
    let errors: [String]

    var successTop50: Bool { targetRank.map { $0 <= 50 } ?? false }
    var successTop200: Bool { targetRank.map { $0 <= 200 } ?? false }
}

struct KakaoMetadataObservation: Codable, Sendable {
    let isbnPresent: Bool
    let isbnMatches: Bool
    let titlePresent: Bool
    let titleMatches: Bool
    let authorPresent: Bool
    let authorMatches: Bool
    let publisherPresent: Bool
    let publisherMatches: Bool
    let publicationDatePresent: Bool
    let publicationDateMatches: Bool
    let descriptionPresent: Bool
    let translatorsPresent: Bool
    let statusPresent: Bool
    let detailURLPresent: Bool
}

struct KakaoCoverObservation: Codable, Sendable {
    let base: CoverObservation
    let finalURL: String?
    let aspectRatio: Double?
    let meetsSearchCellResolution: Bool
    let meetsBookshelfResolution: Bool
}

struct KakaoDetailURLObservation: Codable, Sendable {
    let urlPresent: Bool
    let exactISBNResult: Bool
    let loaded: Bool
    let statusCode: Int?
    let finalURL: String?
    let elapsedMilliseconds: Double?
    let error: String?
}

struct KakaoBookObservation: Codable, Sendable {
    let book: ValidationBook
    let generalTitle: KakaoSearchObservation
    let targetedTitle: KakaoSearchObservation
    let generalAuthor: KakaoSearchObservation
    let targetedAuthor: KakaoSearchObservation
    let generalISBN: KakaoSearchObservation
    let targetedISBN: KakaoSearchObservation
    let representative: KakaoDocument?
    let metadata: KakaoMetadataObservation
    let cover: KakaoCoverObservation
    let detailURL: KakaoDetailURLObservation
}

struct KakaoValidationSummary: Codable, Sendable {
    let generatedAt: Date
    let catalogCount: Int
    let repetitions: Int
    let pageSize: Int
    let maximumResults: Int
    let books: [KakaoBookObservation]
}

func kakaoPublicationDate(_ rawValue: String) -> String? {
    let prefix = rawValue.prefix(10)
    guard prefix.count == 10,
          prefix[prefix.index(prefix.startIndex, offsetBy: 4)] == "-",
          prefix[prefix.index(prefix.startIndex, offsetBy: 7)] == "-" else { return nil }
    return String(prefix)
}

func kakaoHasText(_ value: String?) -> Bool {
    !(value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
}
