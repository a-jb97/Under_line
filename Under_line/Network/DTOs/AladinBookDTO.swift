//
//  AladinBookDTO.swift
//  Under_line
//
//  알라딘 Open API 응답 DTO — 도메인 레이어에 노출하지 않음
//
//  SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor 설정으로 인해
//  Decodable 합성 init이 @MainActor-isolated로 추론되는 문제를 막기 위해
//  nonisolated init(from:)을 명시적으로 구현함
//

import UIKit

// MARK: - Response Wrapper

struct AladinListResponse: Decodable, Sendable {
    let totalResults: Int
    let item: [AladinBookItem]

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalResults  = try container.decode(Int.self,              forKey: .totalResults)
        item          = try container.decode([AladinBookItem].self, forKey: .item)
    }

    private enum CodingKeys: String, CodingKey {
        case totalResults, item
    }
}

// MARK: - SubInfo (상품 조회 API OptResult=subInfo 응답)

struct AladinSubInfo: Decodable, Sendable {
    let itemPage: Int?

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        itemPage = try container.decodeIfPresent(Int.self, forKey: .itemPage)
    }

    private enum CodingKeys: String, CodingKey {
        case itemPage
    }
}

// MARK: - Item

struct AladinBookItem: Decodable, Sendable {
    let title:        String
    let author:       String
    let isbn13:       String
    let cover:        String
    let publisher:    String
    let pubDate:      String?
    let categoryName: String?
    let bestRank:     Int?
    let description:  String
    let subInfo:      AladinSubInfo?  // ItemLookUp.aspx (OptResult=subInfo) 응답에만 존재

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title        = try container.decode(String.self,               forKey: .title)
        author       = try container.decode(String.self,               forKey: .author)
        isbn13       = try container.decode(String.self,               forKey: .isbn13)
        cover        = try container.decode(String.self,               forKey: .cover)
        publisher    = try container.decode(String.self,               forKey: .publisher)
        pubDate      = try container.decodeIfPresent(String.self,      forKey: .pubDate)
        categoryName = try container.decodeIfPresent(String.self,      forKey: .categoryName)
        bestRank     = try container.decodeIfPresent(Int.self,         forKey: .bestRank)
        description  = try container.decode(String.self,               forKey: .description)
        subInfo      = try container.decodeIfPresent(AladinSubInfo.self, forKey: .subInfo)
    }

    private enum CodingKeys: String, CodingKey {
        case title, author, isbn13, cover, publisher, pubDate, categoryName, bestRank, description, subInfo
    }
}

// MARK: - Domain Mapping

extension AladinBookItem {
    /// DTO → 도메인 모델 변환의 유일한 지점
    func toDomain() -> Book {
        Book(
            title:       title.htmlDecoded,
            author:      author,
            isbn13:      isbn13,
            coverURL:    URL(string: cover),
            publisher:   publisher,
            publishDate: pubDate,
            category:    categoryName?.split(separator: ">").last.map(String.init),
            bestRank:    bestRank,
            description: description.htmlDecoded,
            itemPage:    subInfo?.itemPage,
            currentPage: nil
        )
    }
}

// MARK: - Private Helpers

private extension String {
    var htmlDecoded: String {
        guard contains("&") else { return self }
        let data = Data(utf8)
        let opts: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ]
        return (try? NSAttributedString(data: data, options: opts, documentAttributes: nil))?
            .string ?? self
    }
}
