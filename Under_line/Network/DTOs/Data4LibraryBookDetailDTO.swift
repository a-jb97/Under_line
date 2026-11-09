import Foundation

struct Data4LibraryBookDetailResponse: Decodable, Sendable {
    let response: Data4LibraryBookDetailBody

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        response = try container.decode(Data4LibraryBookDetailBody.self, forKey: .response)
    }

    private enum CodingKeys: String, CodingKey { case response }
}

struct Data4LibraryBookDetailBody: Decodable, Sendable {
    let books: [Data4LibraryBookDetailDocument]

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let details = try? container.decode(
            [Data4LibraryBookDetailContainer].self,
            forKey: .details
        ) {
            books = details.map(\.book)
        } else if let detail = try? container.decode(
            Data4LibraryBookDetailContainer.self,
            forKey: .details
        ) {
            books = [detail.book]
        } else {
            books = []
        }
    }

    private enum CodingKeys: String, CodingKey { case details = "detail" }
}

struct Data4LibraryBookDetailContainer: Decodable, Sendable {
    let book: Data4LibraryBookDetailDocument

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        book = try container.decode(Data4LibraryBookDetailDocument.self, forKey: .book)
    }

    private enum CodingKeys: String, CodingKey { case book }
}

struct Data4LibraryBookDetailDocument: Decodable, Sendable {
    let title: String
    let authors: String
    let publisher: String
    let publicationDate: String?
    let isbn13: String
    let bookImageURL: String?
    let description: String

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = container.decodeFlexibleString(forKey: .title) ?? ""
        authors = container.decodeFlexibleString(forKey: .authors) ?? ""
        publisher = container.decodeFlexibleString(forKey: .publisher) ?? ""
        publicationDate = container.decodeFlexibleString(forKey: .publicationDate)
        isbn13 = container.decodeFlexibleString(forKey: .isbn13) ?? ""
        bookImageURL = container.decodeFlexibleString(forKey: .bookImageURL)
        description = container.decodeFlexibleString(forKey: .description) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case title = "bookname"
        case authors, publisher
        case publicationDate = "publication_date"
        case isbn13, bookImageURL, description
    }
}

extension Data4LibraryBookDetailDocument {
    func toMetadata() -> BookDetailMetadata? {
        guard let normalizedISBN = ISBN13Parser.isbn13(in: isbn13) else { return nil }
        let normalizedCover = bookImageURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        return BookDetailMetadata(
            isbn13: normalizedISBN,
            title: HTMLTextDecoder.decode(title),
            author: HTMLTextDecoder.decode(authors),
            publisher: HTMLTextDecoder.decode(publisher),
            publishDate: publicationDate?.nilIfBlank,
            coverURL: normalizedCover.flatMap(URL.init(string:)),
            description: HTMLTextDecoder.decode(description)
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
}
