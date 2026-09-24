import Foundation
import ValidationCore

struct NLKDocument: Codable, Sendable {
    let title: String?
    let author: String?
    let isbn13: String?
    let publisher: String?
    let publishPredate: String?
    let titleURL: String?
    let introductionURL: String?
    let introduction: String?
    let page: String?
    let editionStatement: String?
    let form: String?
    let formDetail: String?
    let ebookYN: String?
    let inputDate: String?
    let updateDate: String?
    let depositYN: String?

    init(dictionary: [String: Any]) {
        title = dictionary.nlkString("TITLE")
        author = dictionary.nlkString("AUTHOR")
        isbn13 = dictionary.nlkString("EA_ISBN")
        publisher = dictionary.nlkString("PUBLISHER")
        publishPredate = dictionary.nlkString("PUBLISH_PREDATE")
        titleURL = dictionary.nlkString("TITLE_URL")
        introductionURL = dictionary.nlkString("BOOK_INTRODUCTION_URL")
        introduction = dictionary.nlkString("BOOK_INTRODUCTION")
        page = dictionary.nlkString("PAGE")
        editionStatement = dictionary.nlkString("EDITION_STMT")
        form = dictionary.nlkString("FORM")
        formDetail = dictionary.nlkString("FORM_DETAIL")
        ebookYN = dictionary.nlkString("EBOOK_YN")
        inputDate = dictionary.nlkString("INPUT_DATE")
        updateDate = dictionary.nlkString("UPDATE_DATE")
        depositYN = dictionary.nlkString("DEPOSIT_YN")
    }
}

struct TimedSearchResult: Sendable {
    let documents: [NLKDocument]
    let totalCount: Int?
    let pageSize: Int
    let elapsedMilliseconds: Double
    let pageTimingsMilliseconds: [Double]
}

struct SearchObservation: Codable, Sendable {
    let success: Bool
    let targetRank: Int?
    let resultCount: Int
    let totalCount: Int?
    let timingsMilliseconds: [Double]
    let pageTimingsMilliseconds: [[Double]]
    let repetitionMatches: [Bool]
    let otherEditionOnly: Bool
    let errors: [String]
}

struct NLKCoverObservation: Codable, Sendable {
    let base: CoverObservation
    let aspectRatio: Double?
    let meetsSearchCellResolution: Bool
    let meetsBookshelfResolution: Bool
    let finalURL: String?
}

struct IntroductionObservation: Codable, Sendable {
    let directTextPresent: Bool
    let urlPresent: Bool
    let urlLoaded: Bool
    let statusCode: Int?
    let mimeType: String?
    let finalURL: String?
    let textObtained: Bool
    let source: String?
    let characterCount: Int?
    let elapsedMilliseconds: Double?
    let error: String?
}

struct PageCountObservation: Codable, Sendable {
    let rawValue: String?
    let parsedValue: Int?
    let parseStatus: String
    let expectedValue: Int?
    let matchesExpected: Bool?
    let groundTruthSource: String?
}

struct MetadataObservation: Codable, Sendable {
    let isbnPresent: Bool
    let isbnMatches: Bool
    let titlePresent: Bool
    let titleMatches: Bool
    let authorPresent: Bool
    let authorMatches: Bool
    let publisherPresent: Bool
    let publisherMatches: Bool
    let publishPredatePresent: Bool
    let publishPredateMatches: Bool
    let editionPresent: Bool
    let formPresent: Bool
    let inputDatePresent: Bool
    let updateDatePresent: Bool
}

struct NLKBookObservation: Codable, Sendable {
    let book: ValidationBook
    let titleSearch: SearchObservation
    let authorSearch: SearchObservation
    let isbnSearch: SearchObservation
    let representative: NLKDocument?
    let metadata: MetadataObservation
    let cover: NLKCoverObservation
    let introduction: IntroductionObservation
    let pageCount: PageCountObservation
}

struct LatestBooksObservation: Codable, Sendable {
    let requestedDateRange: String
    let resultCount: Int
    let uniqueISBNCount: Int
    let datesWithinRange: Bool
    let descendingOrder: Bool
    let printOnly: Bool
    let repetitionsStable: Bool
    let formFilteredCount: Int?
    let depositedCount: Int?
    let timingsMilliseconds: [Double]
    let errors: [String]
}

struct NLKValidationSummary: Codable, Sendable {
    let generatedAt: Date
    let catalogCount: Int
    let repetitions: Int
    let acceptedPageSize: Int
    let books: [NLKBookObservation]
    let latestBooks: LatestBooksObservation?
}

struct PageGroundTruth: Codable, Sendable {
    let isbn13: String
    let expectedPageCount: Int
    let source: String
}

extension Dictionary where Key == String, Value == Any {
    func nlkString(_ key: String) -> String? {
        let value = self[key] ?? first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value
        guard let value, !(value is NSNull) else { return nil }
        let string: String
        if let value = value as? String {
            string = value
        } else if let value = value as? NSNumber {
            string = value.stringValue
        } else {
            return nil
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum NLKJSON {
    static func documents(in value: Any) -> [[String: Any]] {
        var matches: [[String: Any]] = []
        collectDocuments(value, into: &matches)
        return matches
    }

    static func integer(for key: String, in value: Any) -> Int? {
        if let dictionary = value as? [String: Any] {
            if let raw = dictionary.nlkString(key), let number = Int(raw.replacingOccurrences(of: ",", with: "")) {
                return number
            }
            for child in dictionary.values {
                if let found = integer(for: key, in: child) { return found }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let found = integer(for: key, in: child) { return found }
            }
        }
        return nil
    }

    static func applicationError(in value: Any) -> (code: String, message: String)? {
        if let dictionary = value as? [String: Any] {
            let codeKeys = ["ERROR_CODE", "errorCode", "ERR_CODE", "errCode", "ERROR", "error"]
            for key in codeKeys {
                if let code = dictionary.nlkString(key),
                   code.range(of: "^[0-9]{3}$", options: .regularExpression) != nil,
                   code != "200" {
                    let message = dictionary.nlkString("ERROR_MESSAGE")
                        ?? dictionary.nlkString("message")
                        ?? dictionary.nlkString("ERROR_MSG")
                        ?? "국립중앙도서관 API 오류"
                    return (code, message)
                }
            }
            for child in dictionary.values {
                if let found = applicationError(in: child) { return found }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let found = applicationError(in: child) { return found }
            }
        }
        return nil
    }

    static func removingSensitiveValues(from value: Any) -> Any {
        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: [String: Any]()) { result, pair in
                if pair.key.lowercased() == "cert_key" {
                    result[pair.key] = "[REDACTED]"
                } else {
                    result[pair.key] = removingSensitiveValues(from: pair.value)
                }
            }
        }
        if let array = value as? [Any] { return array.map(removingSensitiveValues) }
        return value
    }

    private static func collectDocuments(_ value: Any, into result: inout [[String: Any]]) {
        if let dictionary = value as? [String: Any] {
            let keys = Set(dictionary.keys.map { $0.uppercased() })
            if keys.contains("EA_ISBN") || (keys.contains("TITLE") && keys.contains("PUBLISHER")) {
                result.append(dictionary)
                return
            }
            for child in dictionary.values { collectDocuments(child, into: &result) }
        } else if let array = value as? [Any] {
            for child in array { collectDocuments(child, into: &result) }
        }
    }
}

enum PageCountParser {
    static func parse(_ rawValue: String?) -> (value: Int?, status: String) {
        guard let rawValue else { return (nil, "missing") }
        let normalized = rawValue.replacingOccurrences(of: ",", with: "")
        guard let expression = try? NSRegularExpression(pattern: "(?<![0-9])[0-9]{1,5}(?![0-9])") else {
            return (nil, "invalid")
        }
        let range = NSRange(normalized.startIndex..., in: normalized)
        let values = expression.matches(in: normalized, range: range).compactMap { match -> Int? in
            guard let range = Range(match.range, in: normalized) else { return nil }
            return Int(normalized[range])
        }.filter { $0 > 0 }
        guard values.count == 1, let value = values.first else {
            return (nil, values.isEmpty ? "unparseable" : "ambiguous")
        }
        return (value, "parsed")
    }
}
