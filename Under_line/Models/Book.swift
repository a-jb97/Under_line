//
//  Book.swift
//  Under_line
//
//  도메인 모델 — 네트워크/persistence 세부사항에 의존하지 않음
//

import Foundation

struct Book {
    let title: String
    let author: String
    let isbn13: String
    let coverURL: URL?
    let publisher: String
    let publishDate: String?    // 출판일
    let category: String?       // 도서 카테고리
    let bestRank: Int?           // 순위형 목록에서만 값, 검색 결과는 nil
    let description: String
    let itemPage: Int?           // 사용자가 입력한 책 전체 페이지 수
    let currentPage: Int?        // 사용자가 기록한 현재 읽은 페이지 (로컬 DB)
}

struct BookListMetadata {
    let isbn13: String
    let coverURL: URL?
    let description: String

    init(isbn13: String, coverURL: URL?, description: String) {
        self.isbn13 = isbn13
        self.coverURL = coverURL
        self.description = description
    }

    init(book: Book) {
        isbn13 = book.isbn13
        coverURL = book.coverURL
        description = book.description
    }
}

struct BookDetailMetadata {
    let isbn13: String
    let title: String
    let author: String
    let publisher: String
    let publishDate: String?
    let coverURL: URL?
    let description: String
    var category: String? = nil
}

enum BookGenre {
    static let unknown = "장르 미상"

    static func known(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "미정" || trimmed == unknown ? nil : trimmed
    }

    static func normalized(_ value: String?) -> String {
        known(value) ?? unknown
    }
}

enum LibraryAuthor {
    static func normalized(_ value: String) -> String {
        HTMLTextDecoder.decode(value)
            .replacingOccurrences(of: #"^\s*(?:(?:지은이|저자)\s*[:：]\s*)+"#,
                                  with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension Book {
    var searchAuthorText: String {
        let name = author.trimmingCharacters(in: .whitespacesAndNewlines)
        return "지은이 : \(name.isEmpty ? "알 수 없음" : name)"
    }

    var displayTitle: String {
        guard let colon = title.firstIndex(where: { $0 == ":" || $0 == "：" }) else {
            return title
        }
        let subtitle = String(title[title.index(after: colon)...])
        let authorNames = author
            .components(separatedBy: CharacterSet(charactersIn: ",; /·&\n"))
            .map { name in
                name.replacingOccurrences(
                    of: #"^(?:지은이|저자)\s*[:：]?\s*|\s*(?:\(지은이\)|지음|저)$"#,
                    with: "",
                    options: .regularExpression
                ).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
        guard authorNames.contains(where: { subtitle.contains($0) }) else { return title }
        let mainTitle = String(title[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
        return mainTitle.isEmpty ? title : mainTitle
    }

    func mergingListMetadata(from metadata: BookListMetadata) -> Book {
        guard isbn13 == metadata.isbn13 else { return self }
        let normalizedDescription = metadata.description.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return Book(
            title: title,
            author: author,
            isbn13: isbn13,
            coverURL: metadata.coverURL ?? coverURL,
            publisher: publisher,
            publishDate: publishDate,
            category: category,
            bestRank: bestRank,
            description: normalizedDescription.isEmpty ? description : metadata.description,
            itemPage: itemPage,
            currentPage: currentPage
        )
    }

    func mergingDetailMetadata(from metadata: BookDetailMetadata) -> Book {
        guard isbn13 == metadata.isbn13 else { return self }
        return Book(
            title: title.value(or: metadata.title),
            author: author.value(or: metadata.author),
            isbn13: isbn13,
            coverURL: coverURL ?? metadata.coverURL,
            publisher: publisher.value(or: metadata.publisher),
            publishDate: publishDate.value(or: metadata.publishDate),
            category: BookGenre.known(metadata.category) ?? BookGenre.known(category),
            bestRank: bestRank,
            description: metadata.description.value(or: description),
            itemPage: itemPage,
            currentPage: currentPage
        )
    }
}

private extension String {
    func value(or fallback: String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : self
    }
}

private extension Optional where Wrapped == String {
    func value(or fallback: String?) -> String? {
        guard let self, !self.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return fallback
        }
        return self
    }
}
