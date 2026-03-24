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
    let bestRank: Int?           // 베스트셀러 응답일 때만 값, 검색 결과는 nil
    let description: String
}
