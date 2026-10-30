import Foundation
import ValidationCore

enum KakaoReportWriter {
    static func write(summary: KakaoValidationSummary, to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(summary).write(to: directory.appendingPathComponent("summary.json"), options: .atomic)
        try Data(csv(summary).utf8).write(to: directory.appendingPathComponent("books.csv"), options: .atomic)
        try Data(markdown(summary).utf8).write(to: directory.appendingPathComponent("report.md"), options: .atomic)
        try Data(comparison(summary).utf8).write(to: directory.appendingPathComponent("comparison.md"), options: .atomic)
        try comparisonJSON(summary).write(to: directory.appendingPathComponent("comparison.json"), options: .atomic)
    }

    private static func csv(_ summary: KakaoValidationSummary) -> String {
        let header = [
            "id", "title_query", "author_query", "isbn13", "recency",
            "general_title_top50", "general_title_rank", "targeted_title_top50", "targeted_title_rank",
            "general_author_top50", "general_author_rank", "targeted_author_top50", "targeted_author_rank",
            "general_isbn_top50", "general_isbn_rank", "targeted_isbn_top50", "targeted_isbn_rank",
            "general_title_other_edition", "general_author_other_edition",
            "returned_title", "returned_authors", "returned_isbn", "returned_publisher", "returned_datetime",
            "title_matches", "author_matches", "publisher_matches", "publication_date_matches",
            "description_present", "translators", "status", "detail_url", "detail_url_loaded",
            "cover_url", "cover_loaded", "cover_width", "cover_height", "cover_aspect_ratio",
            "cover_search_cell", "cover_bookshelf", "general_first_page_average_ms",
            "general_cumulative_average_ms", "targeted_first_page_average_ms",
            "targeted_cumulative_average_ms", "errors"
        ]
        let rows = summary.books.map { item -> [String] in
            let general = [item.generalTitle, item.generalAuthor, item.generalISBN]
            let targeted = [item.targetedTitle, item.targetedAuthor, item.targetedISBN]
            let errors = (general + targeted).flatMap(\.errors)
            return [
                item.book.id, item.book.titleQuery, item.book.authorQuery, item.book.isbn13, item.book.recency,
                flag(item.generalTitle.successTop50), value(item.generalTitle.targetRank),
                flag(item.targetedTitle.successTop50), value(item.targetedTitle.targetRank),
                flag(item.generalAuthor.successTop50), value(item.generalAuthor.targetRank),
                flag(item.targetedAuthor.successTop50), value(item.targetedAuthor.targetRank),
                flag(item.generalISBN.successTop50), value(item.generalISBN.targetRank),
                flag(item.targetedISBN.successTop50), value(item.targetedISBN.targetRank),
                flag(item.generalTitle.otherEditionOnly), flag(item.generalAuthor.otherEditionOnly),
                item.representative?.title ?? "", item.representative?.authors.joined(separator: " | ") ?? "",
                item.representative?.isbn ?? "", item.representative?.publisher ?? "",
                item.representative?.datetime ?? "", flag(item.metadata.titleMatches),
                flag(item.metadata.authorMatches), flag(item.metadata.publisherMatches),
                flag(item.metadata.publicationDateMatches), flag(item.metadata.descriptionPresent),
                item.representative?.translators.joined(separator: " | ") ?? "",
                item.representative?.status ?? "", item.representative?.url ?? "",
                flag(item.detailURL.loaded), item.representative?.thumbnail ?? "",
                flag(item.cover.base.loaded), value(item.cover.base.pixelWidth), value(item.cover.base.pixelHeight),
                format(item.cover.aspectRatio), flag(item.cover.meetsSearchCellResolution),
                flag(item.cover.meetsBookshelfResolution),
                format(validationAverage(general.flatMap(\.firstPageTimingsMilliseconds))),
                format(validationAverage(general.flatMap(\.cumulativeTimingsMilliseconds))),
                format(validationAverage(targeted.flatMap(\.firstPageTimingsMilliseconds))),
                format(validationAverage(targeted.flatMap(\.cumulativeTimingsMilliseconds))),
                errors.joined(separator: " | ")
            ]
        }
        return ([header] + rows).map { $0.map(csvEscape).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    private static func markdown(_ summary: KakaoValidationSummary) -> String {
        let books = summary.books
        let recent = books.filter { $0.book.recency == "최근 2년" }
        let generalTitle = rate(books, \.generalTitle.successTop50)
        let generalAuthor = rate(books, \.generalAuthor.successTop50)
        let generalISBN = rate(books, \.generalISBN.successTop50)
        let targetedTitle = rate(books, \.targetedTitle.successTop50)
        let targetedAuthor = rate(books, \.targetedAuthor.successTop50)
        let targetedISBN = rate(books, \.targetedISBN.successTop50)
        let recentGeneralTitle = rate(recent, \.generalTitle.successTop50)
        let recentGeneralAuthor = rate(recent, \.generalAuthor.successTop50)
        let recentGeneralISBN = rate(recent, \.generalISBN.successTop50)
        let recentTargetedTitle = rate(recent, \.targetedTitle.successTop50)
        let recentTargetedAuthor = rate(recent, \.targetedAuthor.successTop50)
        let recentTargetedISBN = rate(recent, \.targetedISBN.successTop50)
        let covers = books.filter { $0.cover.base.urlPresent }
        let loadedCovers = books.filter { $0.cover.base.loaded }
        let widths = loadedCovers.compactMap { $0.cover.base.pixelWidth }.map(Double.init)
        let generalObservations = books.flatMap { [$0.generalTitle, $0.generalAuthor, $0.generalISBN] }
        let targetedObservations = books.flatMap { [$0.targetedTitle, $0.targetedAuthor, $0.targetedISBN] }
        let generalFirstPage = generalObservations.flatMap(\.firstPageTimingsMilliseconds)
        let generalCumulative = generalObservations.flatMap(\.cumulativeTimingsMilliseconds)
        let targetedFirstPage = targetedObservations.flatMap(\.firstPageTimingsMilliseconds)
        let targetedCumulative = targetedObservations.flatMap(\.cumulativeTimingsMilliseconds)
        let allObservations = generalObservations + targetedObservations
        let errorCount = allObservations.reduce(0) { $0 + $1.errors.count }
        let trials = books.count * summary.repetitions * 6
        let errorRate = trials == 0 ? 0 : Double(errorCount) / Double(trials) * 100

        let accuracyPass = generalTitle.successes >= 24 && generalAuthor.successes >= 24
            && generalISBN.successes == 25 && recentGeneralTitle.successes >= 14
            && recentGeneralAuthor.successes >= 14 && recentGeneralISBN.successes == 15
        let metadataPass = count(books, \.metadata.isbnMatches) >= 24
            && count(books, \.metadata.titleMatches) >= 24
            && count(books, \.metadata.authorMatches) >= 24
            && count(books, \.metadata.publisherMatches) >= 24
            && count(books, \.metadata.publicationDateMatches) >= 24
        let performancePass = validationPercentile(generalFirstPage, 0.95) <= 3_000 && errorRate < 1
        let coverPass = books.filter { $0.cover.meetsSearchCellResolution }.count >= 23
            && books.filter { $0.cover.meetsBookshelfResolution }.count >= 23
        let targetedAccuracyPass = targetedTitle.successes >= 24 && targetedAuthor.successes >= 24
            && targetedISBN.successes == 25 && recentTargetedTitle.successes >= 14
            && recentTargetedAuthor.successes >= 14 && recentTargetedISBN.successes == 15
        let dataDecision: String
        if accuracyPass && performancePass {
            if metadataPass {
                dataDecision = coverPass
                    ? "검색·메타데이터·표지 데이터 기준 통과 후보"
                    : "검색·메타데이터 기준 통과 후보 — 고해상도 표지는 별도 소스 필요"
            } else {
                dataDecision = "검색 기준 통과 — 메타데이터 정확도 미달 항목은 기대값과 개별 대조 필요"
            }
        } else if targetedAccuracyPass {
            dataDecision = "필드 지정 검색만 통과 후보 — 현재 단일 검색 UX 유지 시 채택 불가"
        } else {
            dataDecision = "검색 데이터 기준 미달 — 다른 검색 API 또는 UX 변경 검토"
        }

        return """
        # 카카오 책 검색 API 검증 결과

        - 생성 시각: \(iso8601(summary.generatedAt))
        - 표본: \(summary.catalogCount)권, 검색별 \(summary.repetitions)회 반복
        - 검색 범위: 페이지당 \(summary.pageSize)건, 최대 \(summary.maximumResults)건
        - 데이터 판정: **\(dataDecision)**
        - 프로덕션 판정: **밑줄의 메인 도서 검색 API로 채택**
        - 전체 페이지 수: **API 미지원 — 기존 사용자 입력 유지**

        ## 현재 단일 검색창 기준: 일반 검색 Top 50

        | 지표 | 전체 | 최근 2년 | 합격선 |
        |---|---:|---:|---:|
        | 제목 검색 | \(rateText(generalTitle)) | \(rateText(recentGeneralTitle)) | 24/25, 14/15 |
        | 저자 검색 | \(rateText(generalAuthor)) | \(rateText(recentGeneralAuthor)) | 24/25, 14/15 |
        | ISBN 검색 | \(rateText(generalISBN)) | \(rateText(recentGeneralISBN)) | 25/25, 15/15 |

        ## 필드 지정 검색 Top 50

        | 지표 | 전체 | 최근 2년 |
        |---|---:|---:|
        | `target=title` | \(rateText(targetedTitle)) | \(rateText(recentTargetedTitle)) |
        | `target=person` | \(rateText(targetedAuthor)) | \(rateText(recentTargetedAuthor)) |
        | `target=isbn` | \(rateText(targetedISBN)) | \(rateText(recentTargetedISBN)) |

        ## 기본 메타데이터

        | 지표 | 제공/일치 |
        |---|---:|
        | ISBN13 제공 | \(count(books, \.metadata.isbnPresent))/25 |
        | ISBN13 정확 일치 | \(count(books, \.metadata.isbnMatches))/25 |
        | 제목 제공 / 일치 | \(count(books, \.metadata.titlePresent))/25 / \(count(books, \.metadata.titleMatches))/25 |
        | 저자 제공 / 일치 | \(count(books, \.metadata.authorPresent))/25 / \(count(books, \.metadata.authorMatches))/25 |
        | 출판사 제공 / 일치 | \(count(books, \.metadata.publisherPresent))/25 / \(count(books, \.metadata.publisherMatches))/25 |
        | 출판일 제공 / 일치 | \(count(books, \.metadata.publicationDatePresent))/25 / \(count(books, \.metadata.publicationDateMatches))/25 |
        | 책소개 제공 | \(count(books, \.metadata.descriptionPresent))/25 |
        | 번역자 제공 | \(count(books, \.metadata.translatorsPresent))/25 |
        | 상태 문자열 제공 | \(count(books, \.metadata.statusPresent))/25 |
        | Daum 상세 URL 제공 / 로딩 | \(count(books, \.detailURL.urlPresent))/25 / \(count(books, \.detailURL.loaded))/25 |
        | Daum 상세 URL 기대 ISBN 연계 | \(count(books, \.detailURL.exactISBNResult))/25 |

        - 판매 상태 원문 빈도: \(statusSummary(books))

        ## 표지

        | 지표 | 결과 |
        |---|---:|
        | URL 제공 | \(covers.count)/25 |
        | 실제 로딩 | \(loadedCovers.count)/25 |
        | 검색 셀 144×192px 충족 | \(books.filter { $0.cover.meetsSearchCellResolution }.count)/25 |
        | 3배율 책장 264×351px 충족 | \(books.filter { $0.cover.meetsBookshelfResolution }.count)/25 |

        - width 평균/Median/최소/최대: \(format(validationAverage(widths))) / \(format(validationMedian(widths))) / \(format(widths.min())) / \(format(widths.max())) px
        - 표지 기준이 미달해도 검색 채택 여부와 분리해 판정한다.

        ## 응답 성능

        | 방식 | 평균 | Median | P95 | 최소 | 최대 |
        |---|---:|---:|---:|---:|---:|
        | 일반 검색 첫 페이지 | \(stats(generalFirstPage)) |
        | 일반 검색 최대 200건 누적 | \(stats(generalCumulative)) |
        | 필드 검색 첫 페이지 | \(stats(targetedFirstPage)) |
        | 필드 검색 최대 200건 누적 | \(stats(targetedCumulative)) |

        - 검색 시도 오류율: \(format(errorRate))% (\(errorCount)/\(trials))
        - API가 별도 상세 조회를 제공하지 않아 검색 결과 표시에 추가 상세 API 비용은 없다.

        ## 해석 주의사항

        - 성공은 제목 유사도가 아니라 기대 ISBN13 판본이 결과에 존재하는지로 판정했다.
        - `url`은 Daum 도서 상세 URL이며 서점 구매 URL이 아니다.
        - `status`는 실제 반환 문자열을 보존하며 안정적인 enum으로 해석하지 않는다.
        - REST 호출은 모바일 환경에서도 지원되지만 배포 앱의 키 내장 허용 여부는 공식 확인이 필요하다.
        """
    }

    private static func comparison(_ summary: KakaoValidationSummary) -> String {
        let books = summary.books
        let recent = books.filter { $0.book.recency == "최근 2년" }
        let general = books.flatMap { [$0.generalTitle, $0.generalAuthor, $0.generalISBN] }
        let targeted = books.flatMap { [$0.targetedTitle, $0.targetedAuthor, $0.targetedISBN] }
        let generalTimings = general.flatMap(\.cumulativeTimingsMilliseconds)
        let targetedTimings = targeted.flatMap(\.cumulativeTimingsMilliseconds)
        let generalErrors = general.reduce(0) { $0 + $1.errors.count }
        let targetedErrors = targeted.reduce(0) { $0 + $1.errors.count }
        let modeTrials = books.count * summary.repetitions * 3
        let generalErrorRate = modeTrials == 0 ? 0 : Double(generalErrors) / Double(modeTrials) * 100
        let targetedErrorRate = modeTrials == 0 ? 0 : Double(targetedErrors) / Double(modeTrials) * 100
        return """
        # 정보나루 vs 카카오 책 검색

        | 항목 | 정보나루 | 카카오 일반 | 카카오 필드 지정 |
        |---|---:|---:|---:|
        | 제목 검색 Top 50 | 17/25 | \(successText(books, \.generalTitle.successTop50)) | \(successText(books, \.targetedTitle.successTop50)) |
        | 저자 검색 Top 50 | 16/25 | \(successText(books, \.generalAuthor.successTop50)) | \(successText(books, \.targetedAuthor.successTop50)) |
        | ISBN 검색 Top 50 | 20/25 | \(successText(books, \.generalISBN.successTop50)) | \(successText(books, \.targetedISBN.successTop50)) |
        | 제목 검색 Top 200 | 18/25 | \(successText(books, \.generalTitle.successTop200)) | \(successText(books, \.targetedTitle.successTop200)) |
        | 저자 검색 Top 200 | 19/25 | \(successText(books, \.generalAuthor.successTop200)) | \(successText(books, \.targetedAuthor.successTop200)) |
        | ISBN 검색 Top 200 | 20/25 | \(successText(books, \.generalISBN.successTop200)) | \(successText(books, \.targetedISBN.successTop200)) |
        | 최근 2년 제목 Top 50 | 9/15 | \(successText(recent, \.generalTitle.successTop50)) | \(successText(recent, \.targetedTitle.successTop50)) |
        | 최근 2년 저자 Top 50 | 7/15 | \(successText(recent, \.generalAuthor.successTop50)) | \(successText(recent, \.targetedAuthor.successTop50)) |
        | 최근 2년 ISBN Top 50 | 10/15 | \(successText(recent, \.generalISBN.successTop50)) | \(successText(recent, \.targetedISBN.successTop50)) |
        | 표지 제공 | 25/25 | \(books.filter { $0.cover.base.urlPresent }.count)/25 | 동일 대표 판본 |
        | 표지 로딩 | 25/25 | \(books.filter { $0.cover.base.loaded }.count)/25 | 동일 대표 판본 |
        | 검색 셀 해상도 충족 | 21/25 | \(books.filter { $0.cover.meetsSearchCellResolution }.count)/25 | 동일 대표 판본 |
        | 3배율 책장 충족 | 1/25 | \(books.filter { $0.cover.meetsBookshelfResolution }.count)/25 | 동일 대표 판본 |
        | 책소개 제공 | 22/25 | \(count(books, \.metadata.descriptionPresent))/25 | 동일 대표 판본 |
        | 페이지 수 | 미지원 | 미지원 | 미지원 |
        | 최대 200건 누적 평균 | 63.67ms | \(format(validationAverage(generalTimings)))ms | \(format(validationAverage(targetedTimings)))ms |
        | 최대 200건 누적 P95 | 154.20ms | \(format(validationPercentile(generalTimings, 0.95)))ms | \(format(validationPercentile(targetedTimings, 0.95)))ms |
        | 검색 시도 오류율 | 0% | \(format(generalErrorRate))% | \(format(targetedErrorRate))% |
        | 밑줄 채택 역할 | 목록·상세 보완 | 메인 검색 | 메인 검색 보조 지표 |

        > 카카오 일반 검색은 현재 단일 검색창과 가장 가까운 기준이며, 필드 지정 검색은 API의 잠재 성능을 확인하는 진단 지표다.
        """
    }

    private static func comparisonJSON(_ summary: KakaoValidationSummary) throws -> Data {
        let books = summary.books
        let recent = books.filter { $0.book.recency == "최근 2년" }
        let general = books.flatMap { [$0.generalTitle, $0.generalAuthor, $0.generalISBN] }
        let targeted = books.flatMap { [$0.targetedTitle, $0.targetedAuthor, $0.targetedISBN] }
        let errorCount = (general + targeted).reduce(0) { $0 + $1.errors.count }
        let trials = books.count * summary.repetitions * 6
        let payload: [String: Any] = [
            "generatedAt": iso8601(summary.generatedAt),
            "data4library": [
                "top50Title": 17, "top50Author": 16, "top50ISBN": 20,
                "top200Title": 18, "top200Author": 19, "top200ISBN": 20,
                "recentTop50Title": 9, "recentTop50Author": 7, "recentTop50ISBN": 10,
                "coverProvided": 25, "coverLoaded": 25, "searchCellCover": 21,
                "bookshelfCover": 1, "description": 22,
                "averageSearchMilliseconds": 63.67, "p95SearchMilliseconds": 154.20,
                "apiErrorPercentage": 0
            ],
            "kakaoGeneral": comparisonValues(
                books: books, recent: recent, targeted: false, repetitions: summary.repetitions
            ),
            "kakaoTargeted": comparisonValues(
                books: books, recent: recent, targeted: true, repetitions: summary.repetitions
            ),
            "kakaoShared": [
                "coverProvided": books.filter { $0.cover.base.urlPresent }.count,
                "coverLoaded": books.filter { $0.cover.base.loaded }.count,
                "searchCellCover": books.filter { $0.cover.meetsSearchCellResolution }.count,
                "bookshelfCover": books.filter { $0.cover.meetsBookshelfResolution }.count,
                "description": count(books, \.metadata.descriptionPresent),
                "apiErrorPercentage": trials == 0 ? 0 : Double(errorCount) / Double(trials) * 100,
                "iosDirectCallPolicy": "공식 확인 필요",
                "pageCount": "미지원"
            ]
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }

    private static func comparisonValues(
        books: [KakaoBookObservation],
        recent: [KakaoBookObservation],
        targeted: Bool,
        repetitions: Int
    ) -> [String: Any] {
        let title: (KakaoBookObservation) -> KakaoSearchObservation = targeted ? { $0.targetedTitle } : { $0.generalTitle }
        let author: (KakaoBookObservation) -> KakaoSearchObservation = targeted ? { $0.targetedAuthor } : { $0.generalAuthor }
        let isbn: (KakaoBookObservation) -> KakaoSearchObservation = targeted ? { $0.targetedISBN } : { $0.generalISBN }
        let observations = books.flatMap { [title($0), author($0), isbn($0)] }
        let timings = observations.flatMap(\.cumulativeTimingsMilliseconds)
        let errorCount = observations.reduce(0) { $0 + $1.errors.count }
        let trials = books.count * repetitions * 3
        return [
            "top50Title": books.filter { title($0).successTop50 }.count,
            "top50Author": books.filter { author($0).successTop50 }.count,
            "top50ISBN": books.filter { isbn($0).successTop50 }.count,
            "top200Title": books.filter { title($0).successTop200 }.count,
            "top200Author": books.filter { author($0).successTop200 }.count,
            "top200ISBN": books.filter { isbn($0).successTop200 }.count,
            "recentTop50Title": recent.filter { title($0).successTop50 }.count,
            "recentTop50Author": recent.filter { author($0).successTop50 }.count,
            "recentTop50ISBN": recent.filter { isbn($0).successTop50 }.count,
            "averageCumulativeMilliseconds": validationAverage(timings),
            "p95CumulativeMilliseconds": validationPercentile(timings, 0.95),
            "apiErrorPercentage": trials == 0 ? 0 : Double(errorCount) / Double(trials) * 100
        ]
    }

}

private func rate<T>(_ values: [T], _ keyPath: KeyPath<T, Bool>) -> RateSummary {
    RateSummary(successes: values.filter { $0[keyPath: keyPath] }.count, total: values.count)
}

private func rateText(_ rate: RateSummary) -> String {
    "\(rate.successes)/\(rate.total) (\(format(rate.percentage))%)"
}

private func successText<T>(_ values: [T], _ keyPath: KeyPath<T, Bool>) -> String {
    rateText(rate(values, keyPath))
}

private func count<T>(_ values: [T], _ keyPath: KeyPath<T, Bool>) -> Int {
    values.filter { $0[keyPath: keyPath] }.count
}

private func stats(_ values: [Double]) -> String {
    [
        validationAverage(values), validationMedian(values), validationPercentile(values, 0.95),
        values.min() ?? 0, values.max() ?? 0
    ].map { "\(format($0))ms" }.joined(separator: " | ")
}

private func value<T>(_ value: T?) -> String { value.map(String.init(describing:)) ?? "" }
private func flag(_ value: Bool) -> String { value ? "Y" : "N" }
private func format(_ value: Double?) -> String { value.map { String(format: "%.2f", $0) } ?? "-" }

private func csvEscape(_ value: String) -> String {
    if value.contains(",") || value.contains("\"") || value.contains("\n") {
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
    return value
}

private func iso8601(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
}

private func statusSummary(_ books: [KakaoBookObservation]) -> String {
    let values = books.compactMap { item -> String? in
        guard let status = item.representative?.status.trimmingCharacters(in: .whitespacesAndNewlines),
              !status.isEmpty else { return nil }
        return status
    }
    let counts = Dictionary(grouping: values, by: { $0 }).mapValues(\.count)
    guard !counts.isEmpty else { return "제공 없음" }
    return counts.sorted { lhs, rhs in
        lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
    }.map { "\($0.key) \($0.value)건" }.joined(separator: ", ")
}
