//
//  AladinAPIService.swift
//  Under_line
//
//  알라딘 Open API 네트워크 레이어
//

import Foundation
import Alamofire
import RxSwift

// MARK: - Protocol

protocol AladinAPIServiceProtocol {
    func fetchBestsellers() -> Single<[Book]>
    func searchBooks(query: String, page: Int) -> Single<(books: [Book], totalResults: Int)>
}

// MARK: - Implementation

final class AladinAPIService: AladinAPIServiceProtocol {

    private let baseURL = "https://www.aladin.co.kr/ttb/api/"
    private let apiKey: String

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func fetchBestsellers() -> Single<[Book]> {
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
        return request(endpoint: "ItemList.aspx", parameters: params)
            .map { $0.item.map { $0.toDomain() } }
    }

    func searchBooks(query: String, page: Int) -> Single<(books: [Book], totalResults: Int)> {
        let maxResults = 50
        let params: Parameters = [
            "ttbkey":       apiKey,
            "Query":        query,
            "MaxResults":   maxResults,
            "start":        page,
            "SearchTarget": "Book",
            "Cover":        "Big",
            "output":       "js",
            "Version":      "20131101"
        ]
        return request(endpoint: "ItemSearch.aspx", parameters: params)
            .map { (books: $0.item.map { $0.toDomain() }, totalResults: $0.totalResults) }
    }

    // MARK: - Private

    private func request(endpoint: String, parameters: Parameters) -> Single<AladinListResponse> {
        Single.create { [weak self] observer in
            guard let self else {
                observer(.failure(AladinAPIError.unknown))
                return Disposables.create()
            }
            let task = AF.request(
                self.baseURL + endpoint,
                parameters: parameters,
                encoding: URLEncoding.default
            )
            .validate(statusCode: 200..<300)
            .responseDecodable(of: AladinListResponse.self) { response in
                switch response.result {
                case .success(let dto):
                    observer(.success(dto))
                case .failure(let error):
                    observer(.failure(error))
                }
            }
            return Disposables.create { task.cancel() }
        }
    }
}

// MARK: - Error

enum AladinAPIError: Error {
    case unknown
}
