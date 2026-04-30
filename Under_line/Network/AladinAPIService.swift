//
//  AladinAPIService.swift
//  Under_line
//
//  알라딘 Open API 네트워크 레이어
//

import Foundation
import Alamofire

// MARK: - Protocol

protocol AladinAPIServiceProtocol {
    func fetchBestsellers() async throws -> [Book]
    func searchBooks(query: String, page: Int) async throws -> (books: [Book], totalResults: Int)
    func fetchBookDetail(isbn13: String) async throws -> Book
}

// MARK: - Implementation

final class AladinAPIService: AladinAPIServiceProtocol {

    private let baseURL = "https://www.aladin.co.kr/ttb/api/"
    private let apiKey: String

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func fetchBestsellers() async throws -> [Book] {
        let params: Parameters = [
            "ttbkey":       apiKey,
            "QueryType":    "Bestseller",
            "MaxResults":   50,
            "start":        1,
            "SearchTarget": "Book",
            "Cover":        "Big",
            "output":       "js",
            "Version":      "20131101"
        ]
        let response = try await request(endpoint: "ItemList.aspx", parameters: params)
        return response.item.map { $0.toDomain() }
    }

    func searchBooks(query: String, page: Int) async throws -> (books: [Book], totalResults: Int) {
        let params: Parameters = [
            "ttbkey":       apiKey,
            "Query":        query,
            "MaxResults":   50,
            "start":        page,
            "SearchTarget": "Book",
            "Cover":        "Big",
            "output":       "js",
            "Version":      "20131101"
        ]
        let response = try await request(endpoint: "ItemSearch.aspx", parameters: params)
        return (books: response.item.map { $0.toDomain() }, totalResults: response.totalResults)
    }

    func fetchBookDetail(isbn13: String) async throws -> Book {
        let params: Parameters = [
            "ttbkey":     apiKey,
            "itemIdType": "ISBN13",
            "ItemId":     isbn13,
            "Cover":      "Big",
            "output":     "js",
            "Version":    "20131101",
            "OptResult":  "subInfo"
        ]
        let response = try await request(endpoint: "ItemLookUp.aspx", parameters: params)
        guard let item = response.item.first else { throw AladinAPIError.unknown }
        return item.toDomain()
    }

    // MARK: - Private

    private func request(endpoint: String, parameters: Parameters) async throws -> AladinListResponse {
        try await AF.request(
            baseURL + endpoint,
            parameters: parameters,
            encoding: URLEncoding.default
        )
        .validate(statusCode: 200..<300)
        .serializingDecodable(AladinListResponse.self)
        .value
    }
}

// MARK: - Error

enum AladinAPIError: Error {
    case unknown
}
