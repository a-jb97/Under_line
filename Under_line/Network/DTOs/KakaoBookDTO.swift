import Foundation

struct KakaoBookSearchResponse: Decodable, Sendable {
    let meta: KakaoBookMeta
    let documents: [KakaoBookDocument]

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        meta = try container.decode(KakaoBookMeta.self, forKey: .meta)
        documents = try container.decode([KakaoBookDocument].self, forKey: .documents)
    }

    private enum CodingKeys: String, CodingKey {
        case meta, documents
    }
}

struct KakaoBookMeta: Decodable, Sendable {
    let totalCount: Int
    let pageableCount: Int
    let isEnd: Bool

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalCount = try container.decode(Int.self, forKey: .totalCount)
        pageableCount = try container.decode(Int.self, forKey: .pageableCount)
        isEnd = try container.decode(Bool.self, forKey: .isEnd)
    }

    private enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case pageableCount = "pageable_count"
        case isEnd = "is_end"
    }
}

struct KakaoBookDocument: Decodable, Sendable {
    let title: String
    let contents: String
    let isbn: String
    let datetime: String
    let authors: [String]
    let publisher: String
    let thumbnail: String

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        contents = try container.decodeIfPresent(String.self, forKey: .contents) ?? ""
        isbn = try container.decodeIfPresent(String.self, forKey: .isbn) ?? ""
        datetime = try container.decodeIfPresent(String.self, forKey: .datetime) ?? ""
        authors = try container.decodeIfPresent([String].self, forKey: .authors) ?? []
        publisher = try container.decodeIfPresent(String.self, forKey: .publisher) ?? ""
        thumbnail = try container.decodeIfPresent(String.self, forKey: .thumbnail) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case title, contents, isbn, datetime, authors, publisher, thumbnail
    }
}

struct KakaoBookErrorResponse: Decodable, Sendable {
    let errorType: String?
    let message: String?

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        errorType = try container.decodeIfPresent(String.self, forKey: .errorType)
        message = try container.decodeIfPresent(String.self, forKey: .message)
    }

    private enum CodingKeys: String, CodingKey {
        case errorType, message
    }
}

extension KakaoBookDocument {
    func toDomain() -> Book? {
        guard let isbn13 = ISBN13Parser.isbn13(in: isbn) else { return nil }
        let normalizedThumbnail = thumbnail.trimmingCharacters(in: .whitespacesAndNewlines)
        return Book(
            title: HTMLTextDecoder.decode(title),
            author: authors.joined(separator: ", "),
            isbn13: isbn13,
            coverURL: normalizedThumbnail.isEmpty ? nil : URL(string: normalizedThumbnail),
            publisher: publisher,
            publishDate: kakaoPublicationDate(datetime),
            category: nil,
            bestRank: nil,
            description: HTMLTextDecoder.decode(contents),
            itemPage: nil,
            currentPage: nil
        )
    }
}

private func kakaoPublicationDate(_ rawValue: String) -> String? {
    let prefix = rawValue.prefix(10)
    guard prefix.count == 10 else { return nil }
    let characters = Array(prefix)
    guard characters[4] == "-", characters[7] == "-",
          characters.enumerated().allSatisfy({ index, character in
              index == 4 || index == 7 || character.isNumber
          }) else { return nil }
    return String(prefix)
}
