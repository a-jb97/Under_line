import Foundation
import ValidationCore

enum NLKReportWriter {
    static func write(summary: NLKValidationSummary, to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(summary).write(to: directory.appendingPathComponent("summary.json"), options: .atomic)
        try Data(csv(summary).utf8).write(to: directory.appendingPathComponent("results.csv"), options: .atomic)
        try Data(markdown(summary).utf8).write(to: directory.appendingPathComponent("report.md"), options: .atomic)
        try Data(comparison(summary).utf8).write(to: directory.appendingPathComponent("comparison.md"), options: .atomic)
        try comparisonJSON(summary).write(to: directory.appendingPathComponent("comparison.json"), options: .atomic)
        try Data(policyInquiry.utf8).write(to: directory.appendingPathComponent("policy-inquiry.md"), options: .atomic)
    }

    private static func csv(_ summary: NLKValidationSummary) -> String {
        let header = [
            "id", "title_query", "author_query", "isbn13", "recency",
            "title_found", "title_rank", "title_repetitions", "title_other_edition_only",
            "author_found", "author_rank", "author_repetitions",
            "isbn_found", "isbn_rank", "isbn_repetitions",
            "returned_title", "returned_author", "returned_isbn", "returned_publisher",
            "publish_predate", "edition_stmt", "form", "ebook_yn", "input_date", "update_date",
            "title_matches", "author_matches", "publisher_matches", "publish_predate_matches",
            "cover_url", "cover_loaded", "cover_width", "cover_height", "cover_aspect_ratio",
            "cover_search_cell", "cover_bookshelf",
            "introduction_direct", "introduction_url", "introduction_loaded", "introduction_text_obtained",
            "page_raw", "page_parsed", "page_parse_status", "page_expected", "page_matches",
            "search_average_ms", "errors"
        ]
        let rows = summary.books.map { item -> [String] in
            let timings = item.titleSearch.timingsMilliseconds
                + item.authorSearch.timingsMilliseconds + item.isbnSearch.timingsMilliseconds
            let errors = item.titleSearch.errors + item.authorSearch.errors + item.isbnSearch.errors
            return [
                item.book.id, item.book.titleQuery, item.book.authorQuery, item.book.isbn13, item.book.recency,
                flag(item.titleSearch.success), value(item.titleSearch.targetRank), repetitions(item.titleSearch),
                flag(item.titleSearch.otherEditionOnly),
                flag(item.authorSearch.success), value(item.authorSearch.targetRank), repetitions(item.authorSearch),
                flag(item.isbnSearch.success), value(item.isbnSearch.targetRank), repetitions(item.isbnSearch),
                item.representative?.title ?? "", item.representative?.author ?? "",
                item.representative?.isbn13 ?? "", item.representative?.publisher ?? "",
                item.representative?.publishPredate ?? "", item.representative?.editionStatement ?? "",
                item.representative?.form ?? "", item.representative?.ebookYN ?? "",
                item.representative?.inputDate ?? "", item.representative?.updateDate ?? "",
                flag(item.metadata.titleMatches), flag(item.metadata.authorMatches),
                flag(item.metadata.publisherMatches), flag(item.metadata.publishPredateMatches),
                flag(item.cover.base.urlPresent), flag(item.cover.base.loaded), value(item.cover.base.pixelWidth),
                value(item.cover.base.pixelHeight), format(item.cover.aspectRatio),
                flag(item.cover.meetsSearchCellResolution), flag(item.cover.meetsBookshelfResolution),
                flag(item.introduction.directTextPresent), flag(item.introduction.urlPresent),
                flag(item.introduction.urlLoaded), flag(item.introduction.textObtained),
                item.pageCount.rawValue ?? "", value(item.pageCount.parsedValue), item.pageCount.parseStatus,
                value(item.pageCount.expectedValue), optionalFlag(item.pageCount.matchesExpected),
                format(validationAverage(timings)), errors.joined(separator: " | ")
            ]
        }
        return ([header] + rows).map { $0.map(csvEscape).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    private static func markdown(_ summary: NLKValidationSummary) -> String {
        let books = summary.books
        let title = rate(books.filter { $0.titleSearch.success }.count, books.count)
        let author = rate(books.filter { $0.authorSearch.success }.count, books.count)
        let isbn = rate(books.filter { $0.isbnSearch.success }.count, books.count)
        let recent = books.filter { $0.book.recency == "최근 2년" }
        let recentTitle = rate(recent.filter { $0.titleSearch.success }.count, recent.count)
        let recentAuthor = rate(recent.filter { $0.authorSearch.success }.count, recent.count)
        let recentISBN = rate(recent.filter { $0.isbnSearch.success }.count, recent.count)
        let covers = books.filter { $0.cover.base.urlPresent }
        let loadedCovers = books.filter { $0.cover.base.loaded }
        let widths = loadedCovers.compactMap { $0.cover.base.pixelWidth }.map(Double.init)
        let descriptions = books.filter { $0.introduction.textObtained }.count
        let pages = books.filter { $0.pageCount.rawValue != nil }.count
        let parsedPages = books.filter { $0.pageCount.parsedValue != nil }.count
        let verifiedPages = books.compactMap { $0.pageCount.matchesExpected }
        let timings = books.flatMap {
            $0.titleSearch.timingsMilliseconds + $0.authorSearch.timingsMilliseconds + $0.isbnSearch.timingsMilliseconds
        }
        let errorCount = books.reduce(0) {
            $0 + $1.titleSearch.errors.count + $1.authorSearch.errors.count + $1.isbnSearch.errors.count
        }
        let trials = books.count * summary.repetitions * 3
        let errorRate = trials == 0 ? 0 : Double(errorCount) / Double(trials) * 100
        let policyGate = "공식 정책 확인 필요"
        let dataPass = title.percentage >= 96 && author.percentage >= 96 && isbn.percentage == 100
            && recentTitle.successes >= 14 && recentAuthor.successes >= 14 && recentISBN.successes >= 14
        let decision = dataPass
            ? "데이터 기준 통과 후보 — 인증키의 iOS 직접 사용 허용 답변 전에는 채택 보류"
            : "검색 데이터 기준 미달 — 실패 사례와 부분 보완 가능성을 검토"

        return """
        # 국립중앙도서관 ISBN 서지정보 API 검증 결과

        - 생성 시각: \(iso8601(summary.generatedAt))
        - 표본: \(summary.catalogCount)권, 검색별 \(summary.repetitions)회 반복
        - 실측 허용 page_size: \(summary.acceptedPageSize) (공식 상한이 아닌 실행 시점 관찰값)
        - 인증키 앱 사용 정책: **\(policyGate)**
        - 판정: **\(decision)**

        ## 핵심 검색 지표

        | 지표 | 결과 | 합격선 |
        |---|---:|---:|
        | 제목 검색 | \(rateText(title)) | 24/25 |
        | 저자 검색 | \(rateText(author)) | 24/25 |
        | ISBN 검색 | \(rateText(isbn)) | 25/25 |
        | 최근 2년 제목 검색 | \(rateText(recentTitle)) | 14/15 |
        | 최근 2년 저자 검색 | \(rateText(recentAuthor)) | 14/15 |
        | 최근 2년 ISBN 검색 | \(rateText(recentISBN)) | 14/15 |

        ## 데이터 제공 및 품질

        | 지표 | 결과 |
        |---|---:|
        | ISBN13 정확 일치 | \(count(books, \.metadata.isbnMatches))/25 |
        | 제목 정확도 | \(count(books, \.metadata.titleMatches))/25 |
        | 저자 정확도 | \(count(books, \.metadata.authorMatches))/25 |
        | 출판사 정확도 | \(count(books, \.metadata.publisherMatches))/25 |
        | 출판예정일 기대일 일치 | \(count(books, \.metadata.publishPredateMatches))/25 |
        | 판 정보 제공 | \(count(books, \.metadata.editionPresent))/25 |
        | 표지 URL 제공 | \(covers.count)/25 |
        | 표지 실제 로딩 | \(loadedCovers.count)/25 |
        | 검색 셀 해상도 충족 | \(books.filter { $0.cover.meetsSearchCellResolution }.count)/25 |
        | 3배율 책장 해상도 충족 | \(books.filter { $0.cover.meetsBookshelfResolution }.count)/25 |
        | 책소개 텍스트 획득 | \(descriptions)/25 |
        | PAGE 제공 | \(pages)/25 |
        | PAGE 숫자 파싱 | \(parsedPages)/25 |
        | PAGE 독립 기준 일치 | \(verifiedPages.filter { $0 }.count)/\(verifiedPages.count) |

        - 표지 width 평균/Median/최소/최대: \(format(validationAverage(widths))) / \(format(validationMedian(widths))) / \(format(widths.min())) / \(format(widths.max())) px

        ## 응답 성능

        - 검색 평균: \(format(validationAverage(timings)))ms
        - 검색 Median: \(format(validationMedian(timings)))ms
        - 검색 P95: \(format(validationPercentile(timings, 0.95)))ms
        - 검색 최소/최대: \(format(timings.min())) / \(format(timings.max()))ms
        - API 운영 오류율: \(format(errorRate))% (\(errorCount)/\(trials))

        ## 출판예정일 범위 검색

        \(latestText(summary.latestBooks))

        ## 해석 주의사항

        - `PUBLISH_PREDATE`는 공식적으로 실제 출판일이 아니라 출판예정일이다.
        - `BOOK_INTRODUCTION_URL`은 2021년 2월까지 생성된 책소개 파일 URL이며 직접 텍스트와 구분했다.
        - PAGE 정확도는 `--page-ground-truth`로 독립 기준을 제공한 도서만 판정한다.
        - iOS 앱 내 `cert_key` 포함 허용 여부가 확인되기 전에는 프로덕션 채택 대상으로 판정하지 않는다.
        """
    }

    private static func comparison(_ summary: NLKValidationSummary) -> String {
        let books = summary.books
        let recent = books.filter { $0.book.recency == "최근 2년" }
        let timings = books.flatMap {
            $0.titleSearch.timingsMilliseconds + $0.authorSearch.timingsMilliseconds + $0.isbnSearch.timingsMilliseconds
        }
        let errorCount = books.reduce(0) {
            $0 + $1.titleSearch.errors.count + $1.authorSearch.errors.count + $1.isbnSearch.errors.count
        }
        let trials = books.count * summary.repetitions * 3
        let errorRate = trials == 0 ? 0 : Double(errorCount) / Double(trials) * 100
        return """
        # 정보나루 vs 국립중앙도서관

        | 항목 | 정보나루 | 국립중앙도서관 |
        |---|---:|---:|
        | 제목 검색 성공률 | 18/25 (72%) | \(successText(books, \.titleSearch.success)) |
        | 저자 검색 성공률 | 19/25 (76%) | \(successText(books, \.authorSearch.success)) |
        | ISBN 검색 성공률 | 20/25 (80%) | \(successText(books, \.isbnSearch.success)) |
        | 최근 2년 제목 검색 | 10/15 | \(successText(recent, \.titleSearch.success)) |
        | 최근 2년 저자 검색 | 10/15 | \(successText(recent, \.authorSearch.success)) |
        | 최근 2년 ISBN 검색 | 10/15 | \(successText(recent, \.isbnSearch.success)) |
        | 표지 제공률 | 25/25 | \(books.filter { $0.cover.base.urlPresent }.count)/25 |
        | 표지 로딩 성공 | 25/25 | \(books.filter { $0.cover.base.loaded }.count)/25 |
        | 검색 셀 해상도 충족 | 21/25 | \(books.filter { $0.cover.meetsSearchCellResolution }.count)/25 |
        | 3배율 책장 충족 | 1/25 | \(books.filter { $0.cover.meetsBookshelfResolution }.count)/25 |
        | 책소개 제공률 | 22/25 (88%) | \(books.filter { $0.introduction.textObtained }.count)/25 |
        | 페이지 수 제공률 | 미지원 | \(books.filter { $0.pageCount.rawValue != nil }.count)/25 |
        | 페이지 수 파싱률 | 미지원 | \(books.filter { $0.pageCount.parsedValue != nil }.count)/25 |
        | 평균 검색 응답시간 | 63.67ms | \(format(validationAverage(timings)))ms |
        | 검색 P95 | 154.20ms | \(format(validationPercentile(timings, 0.95)))ms |
        | API 오류율 | 0% | \(format(errorRate))% |
        | iOS 직접 호출 정책 | - | 공식 확인 필요 |

        > 국립중앙도서관 시간은 허용된 page_size로 상위 200건까지 조회한 누적 검색 시간이다.
        """
    }

    private static func comparisonJSON(_ summary: NLKValidationSummary) throws -> Data {
        let books = summary.books
        let recent = books.filter { $0.book.recency == "최근 2년" }
        let timings = books.flatMap {
            $0.titleSearch.timingsMilliseconds + $0.authorSearch.timingsMilliseconds + $0.isbnSearch.timingsMilliseconds
        }
        let errorCount = books.reduce(0) {
            $0 + $1.titleSearch.errors.count + $1.authorSearch.errors.count + $1.isbnSearch.errors.count
        }
        let trials = books.count * summary.repetitions * 3
        let data4Library: [String: Any] = [
            "titleSearch": 18,
            "authorSearch": 19,
            "isbnSearch": 20,
            "recentTitleSearch": 10,
            "recentAuthorSearch": 10,
            "recentISBNSearch": 10,
            "coverProvided": 25,
            "coverLoaded": 25,
            "searchCellCover": 21,
            "bookshelfCover": 1,
            "introduction": 22,
            "averageSearchMilliseconds": 63.67,
            "p95SearchMilliseconds": 154.20,
            "apiErrorPercentage": 0
        ]
        let nationalLibrary: [String: Any] = [
            "titleSearch": books.filter { $0.titleSearch.success }.count,
            "authorSearch": books.filter { $0.authorSearch.success }.count,
            "isbnSearch": books.filter { $0.isbnSearch.success }.count,
            "recentTitleSearch": recent.filter { $0.titleSearch.success }.count,
            "recentAuthorSearch": recent.filter { $0.authorSearch.success }.count,
            "recentISBNSearch": recent.filter { $0.isbnSearch.success }.count,
            "coverProvided": books.filter { $0.cover.base.urlPresent }.count,
            "coverLoaded": books.filter { $0.cover.base.loaded }.count,
            "searchCellCover": books.filter { $0.cover.meetsSearchCellResolution }.count,
            "bookshelfCover": books.filter { $0.cover.meetsBookshelfResolution }.count,
            "introduction": books.filter { $0.introduction.textObtained }.count,
            "pageProvided": books.filter { $0.pageCount.rawValue != nil }.count,
            "pageParsed": books.filter { $0.pageCount.parsedValue != nil }.count,
            "averageSearchMilliseconds": validationAverage(timings),
            "p95SearchMilliseconds": validationPercentile(timings, 0.95),
            "apiErrorPercentage": trials == 0 ? 0 : Double(errorCount) / Double(trials) * 100,
            "iosDirectCallPolicy": "공식 확인 필요"
        ]
        let payload: [String: Any] = [
            "generatedAt": iso8601(summary.generatedAt),
            "data4library": data4Library,
            "nationalLibrary": nationalLibrary
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }

    private static let policyInquiry = """
    # 국립중앙도서관 ISBN 서지정보 API 정책 문의 초안

    밑줄 iOS 앱에서 ISBN 서지정보 Open API를 활용하는 방안을 검토하고 있습니다.

    1. App Store에 배포되는 iOS 앱에서 `SearchApi.do`를 직접 호출해도 되는지 확인 부탁드립니다.
    2. `cert_key`를 앱 번들에 포함하는 구조가 허용되는지, 서버 프록시가 필수인지 확인 부탁드립니다.
    3. 인증키 노출 시 폐기·재발급 절차와 이용 제한 정책을 알려주세요.
    4. 상용 앱에서 서지정보·표지·책소개를 표시하고 서비스 범위에서 캐싱할 수 있는지 확인 부탁드립니다.
    5. 출처 표기 의무와 표지·책소개 파일의 재가공 제한이 있는지 알려주세요.
    6. ISBN 서지정보 API의 일일/초당 호출 제한과 최대 `page_size`를 알려주세요.
    7. 허용 IP, 도메인 또는 앱 번들 식별자 제한 기능이 있는지 확인 부탁드립니다.
    """
}

private func rate(_ successes: Int, _ total: Int) -> RateSummary {
    RateSummary(successes: successes, total: total)
}

private func rateText(_ rate: RateSummary) -> String {
    "\(rate.successes)/\(rate.total) (\(format(rate.percentage))%)"
}

private func successText<T>(_ values: [T], _ keyPath: KeyPath<T, Bool>) -> String {
    let successes = values.filter { $0[keyPath: keyPath] }.count
    return "\(successes)/\(values.count) (\(format(values.isEmpty ? 0 : Double(successes) / Double(values.count) * 100))%)"
}

private func count<T>(_ values: [T], _ keyPath: KeyPath<T, Bool>) -> Int {
    values.filter { $0[keyPath: keyPath] }.count
}

private func repetitions(_ observation: SearchObservation) -> String {
    "\(observation.repetitionMatches.filter { $0 }.count)/\(observation.repetitionMatches.count)"
}

private func latestText(_ observation: LatestBooksObservation?) -> String {
    guard let observation else { return "- 측정하지 못함" }
    return """
    - 범위: \(observation.requestedDateRange)
    - 결과: \(observation.resultCount)건, 고유 ISBN \(observation.uniqueISBNCount)건
    - 날짜 범위 준수: \(flag(observation.datesWithinRange)), 내림차순: \(flag(observation.descendingOrder))
    - 인쇄책 조건 준수: \(flag(observation.printOnly)), 3회 결과 안정성: \(flag(observation.repetitionsStable))
    - `form=종이책`: \(value(observation.formFilteredCount))건, `deposit_yn=Y`: \(value(observation.depositedCount))건
    - 평균/P95: \(format(validationAverage(observation.timingsMilliseconds)))/\(format(validationPercentile(observation.timingsMilliseconds, 0.95)))ms
    - 오류: \(observation.errors.count)건
    """
}

private func flag(_ value: Bool) -> String { value ? "Y" : "N" }
private func optionalFlag(_ value: Bool?) -> String { value.map(flag) ?? "" }
private func value<T>(_ value: T?) -> String { value.map(String.init(describing:)) ?? "" }
private func format(_ value: Double?) -> String { value.map { String(format: "%.2f", $0) } ?? "" }
private func format(_ value: Double) -> String { String(format: "%.2f", value) }

private func iso8601(_ date: Date) -> String {
    ISO8601DateFormatter().string(from: date)
}

private func csvEscape(_ value: String) -> String {
    guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
    return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
}
