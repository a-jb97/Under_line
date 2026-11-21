import CryptoKit
import Foundation
import ImageIO
import ValidationCore

enum KakaoValidationError: LocalizedError {
    case invalidResponse
    case http(status: Int, message: String?)
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "유효한 HTTP 응답이 아닙니다."
        case .http(let status, let message):
            return "카카오 API HTTP 오류 \(status)\(message.map { ": \($0)" } ?? "")"
        case .invalidURL:
            return "카카오 API 요청 URL을 만들 수 없습니다."
        }
    }
}

enum KakaoRequestBuilder {
    static let endpoint = URL(string: "https://dapi.kakao.com/v3/search/book")!

    static func searchRequest(
        apiKey: String,
        query: String,
        target: String?,
        sort: String = "accuracy",
        page: Int,
        size: Int,
        timeout: TimeInterval
    ) throws -> URLRequest {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        var values = [
            "query": query,
            "sort": sort,
            "page": String(page),
            "size": String(size)
        ]
        if let target { values["target"] = target }
        components.queryItems = values.sorted { $0.key < $1.key }.map(URLQueryItem.init)
        guard let url = components.url else { throw KakaoValidationError.invalidURL }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("KakaoAK \(apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }
}

private struct KakaoPageResult: Sendable {
    let response: KakaoBookResponse
    let elapsedMilliseconds: Double
}

@MainActor
final class KakaoBookClient {
    private let apiKey: String
    private let timeout: TimeInterval
    private let delayNanoseconds: UInt64
    private let session: URLSession
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

    func preflight() async throws {
        let result = try await search(
            query: "9788937460586",
            target: "isbn",
            maximumResults: 50,
            sampleName: "targeted-isbn"
        )
        guard result.documents.contains(where: { KakaoISBN.contains("9788937460586", in: $0.isbn) }) else {
            throw KakaoValidationError.http(status: 200, message: "기준 ISBN13 판본이 응답에 없습니다.")
        }
    }

    func search(
        query: String,
        target: String?,
        maximumResults: Int = 200,
        sampleName: String? = nil
    ) async throws -> KakaoTimedSearchResult {
        let pageSize = min(50, max(1, maximumResults))
        var documents: [KakaoDocument] = []
        var pageTimings: [Double] = []
        var totalCount = 0
        var pageableCount = 0
        var page = 1

        while documents.count < maximumResults && page <= 50 {
            let result = try await requestPage(
                query: query,
                target: target,
                page: page,
                size: pageSize,
                sampleName: sampleName
            )
            totalCount = result.response.meta.totalCount
            pageableCount = result.response.meta.pageableCount
            pageTimings.append(result.elapsedMilliseconds)
            documents.append(contentsOf: result.response.documents)
            if result.response.meta.isEnd || result.response.documents.isEmpty { break }
            if documents.count >= result.response.meta.pageableCount { break }
            page += 1
        }

        return KakaoTimedSearchResult(
            documents: Array(documents.prefix(maximumResults)),
            totalCount: totalCount,
            pageableCount: pageableCount,
            cumulativeMilliseconds: pageTimings.reduce(0, +),
            firstPageMilliseconds: pageTimings.first ?? 0,
            pageTimingsMilliseconds: pageTimings
        )
    }

    func inspectCover(urlString: String?) async -> KakaoCoverObservation {
        guard let urlString, !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = URL(string: urlString) else {
            return emptyCover(urlPresent: false, error: nil)
        }

        do {
            try await throttle()
            var request = URLRequest(url: url, timeoutInterval: timeout)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let started = ContinuousClock.now
            let (data, response) = try await session.data(for: request)
            let elapsed = milliseconds(since: started)
            guard let http = response as? HTTPURLResponse else { throw KakaoValidationError.invalidResponse }
            let properties = CGImageSourceCreateWithData(data as CFData, nil)
                .flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }
            let width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue
            let height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
            let loaded = (200..<300).contains(http.statusCode)
                && response.mimeType?.hasPrefix("image/") == true && width != nil && height != nil
            let searchCell = loaded && (width ?? 0) >= 144 && (height ?? 0) >= 192
            let bookshelf = loaded && (width ?? 0) >= 264 && (height ?? 0) >= 351
            let hash = loaded ? SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() : nil
            let base = CoverObservation(
                urlPresent: true, loaded: loaded, statusCode: http.statusCode,
                mimeType: response.mimeType, byteCount: data.count, pixelWidth: width,
                pixelHeight: height, meetsResolution: bookshelf, contentHash: hash,
                elapsedMilliseconds: elapsed,
                error: loaded ? nil : "상태·MIME·이미지 디코딩 조건 불충족"
            )
            return KakaoCoverObservation(
                base: base,
                finalURL: response.url?.absoluteString,
                aspectRatio: width.flatMap { width in height.map { Double(width) / Double($0) } },
                meetsSearchCellResolution: searchCell,
                meetsBookshelfResolution: bookshelf
            )
        } catch {
            return emptyCover(urlPresent: true, error: error.localizedDescription)
        }
    }

    func inspectDetailURL(urlString: String?, exactISBNResult: Bool) async -> KakaoDetailURLObservation {
        guard let urlString, !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = URL(string: urlString) else {
            return KakaoDetailURLObservation(
                urlPresent: false, exactISBNResult: exactISBNResult, loaded: false,
                statusCode: nil, finalURL: nil, elapsedMilliseconds: nil, error: nil
            )
        }
        do {
            try await throttle()
            var request = URLRequest(url: url, timeoutInterval: timeout)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let started = ContinuousClock.now
            let (_, response) = try await session.data(for: request)
            let elapsed = milliseconds(since: started)
            guard let http = response as? HTTPURLResponse else { throw KakaoValidationError.invalidResponse }
            let loaded = (200..<400).contains(http.statusCode)
            return KakaoDetailURLObservation(
                urlPresent: true, exactISBNResult: exactISBNResult, loaded: loaded,
                statusCode: http.statusCode, finalURL: response.url?.absoluteString,
                elapsedMilliseconds: elapsed, error: loaded ? nil : "HTTP \(http.statusCode)"
            )
        } catch {
            return KakaoDetailURLObservation(
                urlPresent: true, exactISBNResult: exactISBNResult, loaded: false,
                statusCode: nil, finalURL: nil, elapsedMilliseconds: nil,
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
        query: String,
        target: String?,
        page: Int,
        size: Int,
        sampleName: String?
    ) async throws -> KakaoPageResult {
        try await throttle()
        let request = try KakaoRequestBuilder.searchRequest(
            apiKey: apiKey, query: query, target: target,
            page: page, size: size, timeout: timeout
        )
        let started = ContinuousClock.now
        let (data, response) = try await session.data(for: request)
        let elapsed = milliseconds(since: started)
        guard let http = response as? HTTPURLResponse else { throw KakaoValidationError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw KakaoValidationError.http(status: http.statusCode, message: kakaoErrorMessage(data))
        }
        let decoded = try JSONDecoder().decode(KakaoBookResponse.self, from: data)
        if let sampleName, responseSamples[sampleName] == nil,
           let json = try? JSONSerialization.jsonObject(with: data),
           JSONSerialization.isValidJSONObject(json) {
            responseSamples[sampleName] = try? JSONSerialization.data(
                withJSONObject: json, options: [.prettyPrinted, .sortedKeys]
            )
        }
        return KakaoPageResult(response: decoded, elapsedMilliseconds: elapsed)
    }

    private func throttle() async throws {
        guard delayNanoseconds > 0 else { return }
        try await Task.sleep(nanoseconds: delayNanoseconds)
    }

    private func emptyCover(urlPresent: Bool, error: String?) -> KakaoCoverObservation {
        let base = CoverObservation(
            urlPresent: urlPresent, loaded: false, statusCode: nil, mimeType: nil,
            byteCount: nil, pixelWidth: nil, pixelHeight: nil, meetsResolution: false,
            contentHash: nil, elapsedMilliseconds: nil, error: error
        )
        return KakaoCoverObservation(
            base: base, finalURL: nil, aspectRatio: nil,
            meetsSearchCellResolution: false, meetsBookshelfResolution: false
        )
    }
}

private func kakaoErrorMessage(_ data: Data) -> String? {
    guard let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    return value["message"] as? String ?? value["msg"] as? String
}

private func milliseconds(since instant: ContinuousClock.Instant) -> Double {
    let duration = instant.duration(to: .now)
    return Double(duration.components.seconds) * 1_000
        + Double(duration.components.attoseconds) / 1_000_000_000_000_000
}
