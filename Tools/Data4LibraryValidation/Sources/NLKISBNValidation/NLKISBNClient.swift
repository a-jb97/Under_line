import CryptoKit
import Foundation
import ImageIO
import ValidationCore

enum NLKValidationError: LocalizedError {
    case invalidResponse
    case invalidJSON
    case api(code: String, message: String)
    case http(status: Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "유효한 HTTP 응답이 아닙니다."
        case .invalidJSON:
            return "JSON 응답을 해석할 수 없습니다."
        case .api(let code, let message):
            return "국립중앙도서관 API 오류(\(code)): \(message)"
        case .http(let status):
            return "HTTP 오류: \(status)"
        }
    }
}

private struct PageResult: Sendable {
    let documents: [NLKDocument]
    let totalCount: Int?
    let elapsedMilliseconds: Double
}

@MainActor
final class NLKISBNClient {
    private let apiKey: String
    private let timeout: TimeInterval
    private let delayNanoseconds: UInt64
    private let session: URLSession
    private let endpoint = URL(string: "https://www.nl.go.kr/seoji/SearchApi.do")!
    private var responseSamples: [String: Data] = [:]

    init(apiKey: String, timeout: TimeInterval, delayMilliseconds: Int) {
        self.apiKey = apiKey
        self.timeout = timeout
        delayNanoseconds = UInt64(max(delayMilliseconds, 0)) * 1_000_000

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }

    func preflight() async throws -> Int {
        let result = try await requestPage(
            parameters: ["isbn": "9788937460586", "ebook_yn": "N"],
            page: 1,
            pageSize: 1,
            sampleName: "SearchApi"
        )
        guard result.documents.contains(where: { normalizedISBN13($0.isbn13) == "9788937460586" }) else {
            throw NLKValidationError.api(code: "PREFLIGHT", message: "기준 ISBN이 응답에 없습니다.")
        }
        return try await determineAcceptedPageSize()
    }

    func determineAcceptedPageSize() async throws -> Int {
        var lastError: Error?
        for candidate in [200, 100, 50, 20, 10] {
            do {
                _ = try await requestPage(
                    parameters: ["title": "데미안", "ebook_yn": "N"],
                    page: 1,
                    pageSize: candidate,
                    sampleName: nil
                )
                return candidate
            } catch NLKValidationError.api(let code, _) where code == "013" {
                lastError = NLKValidationError.api(code: code, message: "page_size \(candidate) 제한")
            } catch {
                throw error
            }
        }
        throw lastError ?? NLKValidationError.api(code: "013", message: "허용 page_size를 찾지 못했습니다.")
    }

    func search(
        parameters: [String: String],
        maximumResults: Int,
        pageSize: Int,
        sampleName: String? = nil
    ) async throws -> TimedSearchResult {
        var documents: [NLKDocument] = []
        var pageTimings: [Double] = []
        var totalCount: Int?
        var page = 1
        let resolvedPageSize = min(max(pageSize, 1), maximumResults)

        while documents.count < maximumResults {
            let result = try await requestPage(
                parameters: parameters,
                page: page,
                pageSize: resolvedPageSize,
                sampleName: sampleName
            )
            if totalCount == nil { totalCount = result.totalCount }
            pageTimings.append(result.elapsedMilliseconds)
            documents.append(contentsOf: result.documents)
            if result.documents.count < resolvedPageSize { break }
            if let totalCount, documents.count >= totalCount { break }
            page += 1
        }

        return TimedSearchResult(
            documents: Array(documents.prefix(maximumResults)),
            totalCount: totalCount,
            pageSize: resolvedPageSize,
            elapsedMilliseconds: pageTimings.reduce(0, +),
            pageTimingsMilliseconds: pageTimings
        )
    }

    func inspectCover(urlString: String?) async -> NLKCoverObservation {
        guard let urlString, !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = URL(string: urlString) else {
            let base = CoverObservation(
                urlPresent: false, loaded: false, statusCode: nil, mimeType: nil,
                byteCount: nil, pixelWidth: nil, pixelHeight: nil, meetsResolution: false,
                contentHash: nil, elapsedMilliseconds: nil, error: nil
            )
            return NLKCoverObservation(
                base: base, aspectRatio: nil, meetsSearchCellResolution: false,
                meetsBookshelfResolution: false, finalURL: nil
            )
        }

        do {
            try await throttle()
            var request = URLRequest(url: url, timeoutInterval: timeout)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let started = Date()
            let (data, response) = try await session.data(for: request)
            let elapsed = Date().timeIntervalSince(started) * 1_000
            guard let http = response as? HTTPURLResponse else { throw NLKValidationError.invalidResponse }
            let properties = CGImageSourceCreateWithData(data as CFData, nil)
                .flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }
            let width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue
            let height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
            let loaded = (200..<300).contains(http.statusCode)
                && response.mimeType?.hasPrefix("image/") == true
                && width != nil && height != nil
            let searchCell = loaded && (width ?? 0) >= 144 && (height ?? 0) >= 192
            let bookshelf = loaded && (width ?? 0) >= 264 && (height ?? 0) >= 351
            let digest = loaded ? SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() : nil
            let base = CoverObservation(
                urlPresent: true, loaded: loaded, statusCode: http.statusCode,
                mimeType: response.mimeType, byteCount: data.count, pixelWidth: width,
                pixelHeight: height, meetsResolution: bookshelf, contentHash: digest,
                elapsedMilliseconds: elapsed,
                error: loaded ? nil : "상태·MIME·이미지 디코딩 조건 불충족"
            )
            return NLKCoverObservation(
                base: base,
                aspectRatio: width.flatMap { width in height.map { Double(width) / Double($0) } },
                meetsSearchCellResolution: searchCell,
                meetsBookshelfResolution: bookshelf,
                finalURL: response.url?.absoluteString
            )
        } catch {
            let base = CoverObservation(
                urlPresent: true, loaded: false, statusCode: nil, mimeType: nil,
                byteCount: nil, pixelWidth: nil, pixelHeight: nil, meetsResolution: false,
                contentHash: nil, elapsedMilliseconds: nil, error: error.localizedDescription
            )
            return NLKCoverObservation(
                base: base, aspectRatio: nil, meetsSearchCellResolution: false,
                meetsBookshelfResolution: false, finalURL: nil
            )
        }
    }

    func inspectIntroduction(document: NLKDocument?) async -> IntroductionObservation {
        let direct = document?.introduction?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let direct, !direct.isEmpty {
            return IntroductionObservation(
                directTextPresent: true,
                urlPresent: document?.introductionURL != nil,
                urlLoaded: false,
                statusCode: nil,
                mimeType: nil,
                finalURL: nil,
                textObtained: true,
                source: "BOOK_INTRODUCTION",
                characterCount: direct.count,
                elapsedMilliseconds: nil,
                error: nil
            )
        }

        guard let rawURL = document?.introductionURL,
              let url = URL(string: rawURL) else {
            return IntroductionObservation(
                directTextPresent: false, urlPresent: false, urlLoaded: false,
                statusCode: nil, mimeType: nil, finalURL: nil, textObtained: false,
                source: nil, characterCount: nil, elapsedMilliseconds: nil, error: nil
            )
        }

        do {
            try await throttle()
            var request = URLRequest(url: url, timeoutInterval: timeout)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let started = Date()
            let (data, response) = try await session.data(for: request)
            let elapsed = Date().timeIntervalSince(started) * 1_000
            guard let http = response as? HTTPURLResponse else { throw NLKValidationError.invalidResponse }
            let loaded = (200..<300).contains(http.statusCode)
            let decoded = loaded ? decodedIntroduction(data: data, mimeType: response.mimeType) : nil
            return IntroductionObservation(
                directTextPresent: false,
                urlPresent: true,
                urlLoaded: loaded,
                statusCode: http.statusCode,
                mimeType: response.mimeType,
                finalURL: response.url?.absoluteString,
                textObtained: decoded != nil,
                source: decoded == nil ? nil : "BOOK_INTRODUCTION_URL",
                characterCount: decoded?.count,
                elapsedMilliseconds: elapsed,
                error: loaded ? (decoded == nil ? "응답에서 앱용 텍스트를 추출할 수 없음" : nil) : "HTTP \(http.statusCode)"
            )
        } catch {
            return IntroductionObservation(
                directTextPresent: false, urlPresent: true, urlLoaded: false,
                statusCode: nil, mimeType: nil, finalURL: nil, textObtained: false,
                source: nil, characterCount: nil, elapsedMilliseconds: nil,
                error: error.localizedDescription
            )
        }
    }

    func writeResponseSamples(to directory: URL) throws {
        guard !responseSamples.isEmpty else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, data) in responseSamples {
            try data.write(to: directory.appendingPathComponent("\(name).json"), options: .atomic)
        }
    }

    private func requestPage(
        parameters: [String: String],
        page: Int,
        pageSize: Int,
        sampleName: String?
    ) async throws -> PageResult {
        try await throttle()
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        var query = parameters
        query["cert_key"] = apiKey
        query["result_style"] = "json"
        query["page_no"] = String(page)
        query["page_size"] = String(pageSize)
        components.queryItems = query.sorted { $0.key < $1.key }.map(URLQueryItem.init)
        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let started = Date()
        let (data, response) = try await session.data(for: request)
        let elapsed = Date().timeIntervalSince(started) * 1_000
        guard let http = response as? HTTPURLResponse else { throw NLKValidationError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw NLKValidationError.http(status: http.statusCode) }
        let json = try JSONSerialization.jsonObject(with: data)
        if let error = NLKJSON.applicationError(in: json) {
            throw NLKValidationError.api(code: error.code, message: error.message)
        }
        let dictionaries = NLKJSON.documents(in: json)
        if let sampleName, responseSamples[sampleName] == nil {
            let sanitized = NLKJSON.removingSensitiveValues(from: json)
            responseSamples[sampleName] = try JSONSerialization.data(withJSONObject: sanitized, options: [.prettyPrinted, .sortedKeys])
        }
        return PageResult(
            documents: dictionaries.map(NLKDocument.init),
            totalCount: NLKJSON.integer(for: "TOTAL_COUNT", in: json),
            elapsedMilliseconds: elapsed
        )
    }

    private func throttle() async throws {
        if delayNanoseconds > 0 { try await Task.sleep(nanoseconds: delayNanoseconds) }
    }

    private func decodedIntroduction(data: Data, mimeType: String?) -> String? {
        guard mimeType?.hasPrefix("text/") == true || String(data: data, encoding: .utf8) != nil,
              var string = String(data: data, encoding: .utf8) else { return nil }
        if mimeType == "text/html" || string.localizedCaseInsensitiveContains("<html") {
            string = string.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            string = string.replacingOccurrences(of: "&nbsp;", with: " ")
            string = string.replacingOccurrences(of: "&amp;", with: "&")
        }
        let normalized = string
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return normalized.isEmpty ? nil : normalized
    }
}
