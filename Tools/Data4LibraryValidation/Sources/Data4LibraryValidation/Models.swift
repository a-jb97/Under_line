import Foundation
import ValidationCore

struct BookDocument: Codable, Sendable {
    let title: String?
    let authors: String?
    let publisher: String?
    let publicationYear: String?
    let publicationDate: String?
    let isbn13: String?
    let description: String?
    let coverURL: String?
    let ranking: Int?
    let loanCount: Int?
    let difference: Int?
    let baseWeekRank: Int?
    let pastWeekRank: Int?

    init(dictionary: [String: Any]) {
        title = dictionary.string(for: ["bookname", "title"])
        authors = dictionary.string(for: ["authors", "author"])
        publisher = dictionary.string(for: ["publisher"])
        publicationYear = dictionary.string(for: ["publication_year", "publicationYear", "pubYear"])
        publicationDate = dictionary.string(for: ["publication_date", "publicationDate", "pubDate"])
        isbn13 = dictionary.string(for: ["isbn13"])
        description = dictionary.string(for: ["description"])
        coverURL = dictionary.string(for: ["bookImageURL", "cover", "coverURL"])
        ranking = dictionary.integer(for: ["ranking", "rank"])
        loanCount = dictionary.integer(for: ["loan_count", "loanCount", "loanCnt"])
        difference = dictionary.integer(for: ["difference"])
        baseWeekRank = dictionary.integer(for: ["baseWeekRank", "base_week_rank"])
        pastWeekRank = dictionary.integer(for: ["pastWeekRank", "past_week_rank"])
    }
}

struct TimedDocuments: Sendable {
    let documents: [BookDocument]
    let elapsedMilliseconds: Double
}

struct EndpointObservation: Codable, Sendable {
    let success: Bool
    let targetRank: Int?
    let resultCount: Int
    let timingsMilliseconds: [Double]
    let errors: [String]
}

struct BookObservation: Codable, Sendable {
    let book: ValidationBook
    let titleSearch: EndpointObservation
    let exactTitleSearch: EndpointObservation
    let authorSearch: EndpointObservation
    let isbnSearch: EndpointObservation
    let detailTimingsMilliseconds: [Double]
    let detailErrors: [String]
    let returnedISBN13: String?
    let isbnChecksumValid: Bool
    let titlePresent: Bool
    let authorPresent: Bool
    let publisherPresent: Bool
    let publicationDatePresent: Bool
    let descriptionPresent: Bool
    let cover: CoverObservation
}

struct ListObservation: Codable, Sendable {
    let endpoint: String
    let requestedDateRange: String
    let resultCount: Int
    let uniqueISBNCount: Int
    let rankingCount: Int
    let coverURLCount: Int
    let timingsMilliseconds: [Double]
    let errors: [String]
    let metadata: [String: String]
}

struct ValidationSummary: Codable, Sendable {
    let generatedAt: Date
    let catalogCount: Int
    let repetitions: Int
    let books: [BookObservation]
    let popularBooks: ListObservation?
    let hotTrendBooks: ListObservation?
}


extension Dictionary where Key == String, Value == Any {
    func string(for keys: [String]) -> String? {
        for key in keys {
            guard let value = self[key] else { continue }
            if let string = value as? String {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            } else if let number = value as? NSNumber {
                return number.stringValue
            }
        }
        return nil
    }

    func integer(for keys: [String]) -> Int? {
        guard let string = string(for: keys) else { return nil }
        return Int(string.replacingOccurrences(of: ",", with: ""))
    }
}
