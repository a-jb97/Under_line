import Foundation

struct Data4LibraryPopularResponse: Decodable, Sendable {
    let response: Data4LibraryPopularBody

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        response = try container.decode(Data4LibraryPopularBody.self, forKey: .response)
    }

    private enum CodingKeys: String, CodingKey { case response }
}

struct Data4LibraryPopularBody: Decodable, Sendable {
    let resultCount: Int
    let totalCount: Int
    let documents: [Data4LibraryBookDocument]

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        resultCount = container.decodeFlexibleInt(forKey: .resultCount) ?? 0
        totalCount = container.decodeFlexibleInt(forKey: .totalCount) ?? 0
        documents = try container.decodeIfPresent(
            [Data4LibraryDocumentContainer].self,
            forKey: .documents
        )?.map(\.document) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case resultCount = "resultNum"
        case totalCount = "numFound"
        case documents = "docs"
    }
}

struct Data4LibraryHotTrendResponse: Decodable, Sendable {
    let response: Data4LibraryHotTrendBody

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        response = try container.decode(Data4LibraryHotTrendBody.self, forKey: .response)
    }

    private enum CodingKeys: String, CodingKey { case response }
}

struct Data4LibraryHotTrendBody: Decodable, Sendable {
    let results: [Data4LibraryTrendResult]

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        results = try container.decodeIfPresent(
            [Data4LibraryTrendResultContainer].self,
            forKey: .results
        )?.map(\.result) ?? []
    }

    private enum CodingKeys: String, CodingKey { case results }
}

struct Data4LibraryTrendResultContainer: Decodable, Sendable {
    let result: Data4LibraryTrendResult

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        result = try container.decode(Data4LibraryTrendResult.self, forKey: .result)
    }

    private enum CodingKeys: String, CodingKey { case result }
}

struct Data4LibraryTrendResult: Decodable, Sendable {
    let date: String
    let documents: [Data4LibraryBookDocument]

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = container.decodeFlexibleString(forKey: .date) ?? ""
        documents = try container.decodeIfPresent(
            [Data4LibraryDocumentContainer].self,
            forKey: .documents
        )?.map(\.document) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case date
        case documents = "docs"
    }
}

struct Data4LibraryDocumentContainer: Decodable, Sendable {
    let document: Data4LibraryBookDocument

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        document = try container.decode(Data4LibraryBookDocument.self, forKey: .document)
    }

    private enum CodingKeys: String, CodingKey { case document = "doc" }
}

struct Data4LibraryBookDocument: Decodable, Sendable {
    let sequence: Int?
    let ranking: Int?
    let difference: Int?
    let baseWeekRank: Int?
    let pastWeekRank: Int?
    let title: String
    let authors: String
    let publisher: String
    let publicationYear: String?
    let isbn13: String
    let category: String?
    let bookImageURL: String?
    let detailURL: String?
    let loanCount: Int?

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sequence = container.decodeFlexibleInt(forKey: .sequence)
        ranking = container.decodeFlexibleInt(forKey: .ranking)
        difference = container.decodeFlexibleInt(forKey: .difference)
        baseWeekRank = container.decodeFlexibleInt(forKey: .baseWeekRank)
        pastWeekRank = container.decodeFlexibleInt(forKey: .pastWeekRank)
        title = container.decodeFlexibleString(forKey: .title) ?? ""
        authors = container.decodeFlexibleString(forKey: .authors) ?? ""
        publisher = container.decodeFlexibleString(forKey: .publisher) ?? ""
        publicationYear = container.decodeFlexibleString(forKey: .publicationYear)
        isbn13 = container.decodeFlexibleString(forKey: .isbn13) ?? ""
        category = container.decodeFlexibleString(forKey: .category)
        bookImageURL = container.decodeFlexibleString(forKey: .bookImageURL)
        detailURL = container.decodeFlexibleString(forKey: .detailURL)
        loanCount = container.decodeFlexibleInt(forKey: .loanCount)
    }

    private enum CodingKeys: String, CodingKey {
        case sequence = "no"
        case ranking, difference, baseWeekRank, pastWeekRank
        case title = "bookname"
        case authors, publisher
        case publicationYear = "publication_year"
        case isbn13
        case category = "class_nm"
        case bookImageURL
        case detailURL = "bookDtlUrl"
        case loanCount = "loan_count"
    }
}

extension Data4LibraryBookDocument {
    func toDomain(bestRank: Int?) -> Book? {
        guard let normalizedISBN = ISBN13Parser.isbn13(in: isbn13) else { return nil }
        return Book(
            title: HTMLTextDecoder.decode(title),
            author: LibraryAuthor.normalized(authors),
            isbn13: normalizedISBN,
            coverURL: nil,
            publisher: HTMLTextDecoder.decode(publisher),
            publishDate: publicationYear?.nilIfBlank,
            category: category?.nilIfBlank.map(HTMLTextDecoder.decode),
            bestRank: bestRank,
            description: "",
            itemPage: nil,
            currentPage: nil
        )
    }
}

private extension String {
    nonisolated var nilIfBlank: String? {
        let normalized = trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}

private extension KeyedDecodingContainer {
    nonisolated func decodeFlexibleString(forKey key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return String(value) }
        return nil
    }

    nonisolated func decodeFlexibleInt(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(String.self, forKey: key) { return Int(value) }
        return nil
    }
}
