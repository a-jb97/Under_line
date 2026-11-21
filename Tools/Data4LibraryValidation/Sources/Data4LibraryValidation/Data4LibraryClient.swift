import CryptoKit
import Foundation
import ImageIO
import ValidationCore

enum ValidationError: LocalizedError {
    case invalidResponse
    case api(code: String, message: String)
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "유효한 HTTP 응답이 아닙니다."
        case .api(let code, let message):
            return "API 오류(\(code)): \(message)"
        case .invalidJSON:
            return "JSON 응답을 해석할 수 없습니다."
        }
    }
}

@MainActor
final class Data4LibraryClient {
    private let apiKey: String
    private let timeout: TimeInterval
    private let delayNanoseconds: UInt64
    private let session: URLSession
    private let baseURL = URL(string: "https://data4library.kr/api/")!
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
        _ = try await requestDocuments(
            endpoint: "srchBooks",
            parameters: [
                "isbn13": "9788937460586",
                "exactMatch": "true",
                "pageNo": "1",
                "pageSize": "1"
            ]
        )
    }

    func search(parameters: [String: String], maximumResults: Int = 200) async throws -> TimedDocuments {
        var allDocuments: [BookDocument] = []
        var totalElapsed = 0.0
        var page = 1
        let pageSize = min(max(maximumResults, 1), 200)

        while allDocuments.count < maximumResults {
            var pageParameters = parameters
            pageParameters["pageNo"] = String(page)
            pageParameters["pageSize"] = String(pageSize)
            let result = try await requestDocuments(endpoint: "srchBooks", parameters: pageParameters)
            totalElapsed += result.elapsedMilliseconds
            allDocuments.append(contentsOf: result.documents)
            if result.documents.count < pageSize { break }
            page += 1
        }

        return TimedDocuments(
            documents: Array(allDocuments.prefix(maximumResults)),
            elapsedMilliseconds: totalElapsed
        )
    }

    func detail(isbn13: String) async throws -> TimedDocuments {
        try await requestDocuments(
            endpoint: "srchDtlList",
            parameters: ["isbn13": isbn13, "loaninfoYN": "N"],
            preferredContainerKeys: ["detail", "book"]
        )
    }

    func popular(startDate: String, endDate: String, page: Int = 1, pageSize: Int = 50) async throws -> TimedDocuments {
        try await requestDocuments(endpoint: "loanItemSrch", parameters: [
            "startDt": startDate,
            "endDt": endDate,
            "pageNo": String(page),
            "pageSize": String(pageSize)
        ])
    }

    func hotTrend(searchDate: String) async throws -> TimedDocuments {
        try await requestDocuments(
            endpoint: "hotTrend",
            parameters: ["searchDt": searchDate],
            preferredContainerKeys: ["results", "result", "docs", "doc"]
        )
    }

    func inspectCover(urlString: String?) async -> CoverObservation {
        guard let urlString, !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = URL(string: urlString) else {
            return CoverObservation(
                urlPresent: false, loaded: false, statusCode: nil, mimeType: nil,
                byteCount: nil, pixelWidth: nil, pixelHeight: nil, meetsResolution: false,
                contentHash: nil, elapsedMilliseconds: nil, error: nil
            )
        }

        do {
            try await throttle()
            var request = URLRequest(url: url, timeoutInterval: timeout)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let started = Date()
            let (data, response) = try await session.data(for: request)
            let elapsed = Date().timeIntervalSince(started) * 1_000
            guard let http = response as? HTTPURLResponse else { throw ValidationError.invalidResponse }
            let mimeType = response.mimeType
            let properties = CGImageSourceCreateWithData(data as CFData, nil)
                .flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }
            let width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue
            let height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
            let loaded = (200..<300).contains(http.statusCode)
                && (mimeType?.hasPrefix("image/") == true)
                && width != nil && height != nil
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

            return CoverObservation(
                urlPresent: true,
                loaded: loaded,
                statusCode: http.statusCode,
                mimeType: mimeType,
                byteCount: data.count,
                pixelWidth: width,
                pixelHeight: height,
                meetsResolution: loaded && (width ?? 0) >= 264 && (height ?? 0) >= 351,
                contentHash: loaded ? digest : nil,
                elapsedMilliseconds: elapsed,
                error: loaded ? nil : "상태·MIME·이미지 디코딩 조건 불충족"
            )
        } catch {
            return CoverObservation(
                urlPresent: true, loaded: false, statusCode: nil, mimeType: nil,
                byteCount: nil, pixelWidth: nil, pixelHeight: nil, meetsResolution: false,
                contentHash: nil, elapsedMilliseconds: nil, error: error.localizedDescription
            )
        }
    }

    func writeResponseSamples(to directory: URL) throws {
        guard !responseSamples.isEmpty else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (endpoint, data) in responseSamples {
            try data.write(to: directory.appendingPathComponent("\(endpoint).json"), options: .atomic)
        }
    }

    private func requestDocuments(
        endpoint: String,
        parameters: [String: String],
        preferredContainerKeys: [String] = ["docs", "doc"]
    ) async throws -> TimedDocuments {
        try await throttle()
        var components = URLComponents(url: baseURL.appendingPathComponent(endpoint), resolvingAgainstBaseURL: false)!
        var query = parameters
        query["authKey"] = apiKey
        query["format"] = "json"
        components.queryItems = query.sorted { $0.key < $1.key }.map(URLQueryItem.init)
        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let started = Date()
        let (data, response) = try await session.data(for: request)
        let elapsed = Date().timeIntervalSince(started) * 1_000
        guard let http = response as? HTTPURLResponse else { throw ValidationError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ValidationError.invalidJSON
        }
        if let error = JSONTree.apiError(in: root) {
            throw ValidationError.api(code: error.code, message: error.message)
        }
        captureSample(root, endpoint: endpoint)
        let dictionaries = JSONTree.documentDictionaries(in: root, preferredKeys: preferredContainerKeys)
        return TimedDocuments(
            documents: dictionaries.map(BookDocument.init(dictionary:)),
            elapsedMilliseconds: elapsed
        )
    }

    private func throttle() async throws {
        guard delayNanoseconds > 0 else { return }
        try await Task.sleep(nanoseconds: delayNanoseconds)
    }

    private func captureSample(_ root: [String: Any], endpoint: String) {
        guard responseSamples[endpoint] == nil else { return }
        let sanitized = JSONTree.removingSensitiveValues(from: root)
        guard JSONSerialization.isValidJSONObject(sanitized),
              let data = try? JSONSerialization.data(withJSONObject: sanitized, options: [.prettyPrinted, .sortedKeys]) else {
            return
        }
        responseSamples[endpoint] = data
    }
}

enum JSONTree {
    private static let sensitiveKeys = Set(["authKey", "auth_key", "apiKey", "api_key"])

    static func apiError(in value: Any) -> (code: String, message: String)? {
        if let dictionary = value as? [String: Any] {
            if let code = dictionary.string(for: ["errCode"]),
               let message = dictionary.string(for: ["error", "message"]) {
                return (code, message)
            }
            for child in dictionary.values {
                if let error = apiError(in: child) { return error }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let error = apiError(in: child) { return error }
            }
        }
        return nil
    }

    static func documentDictionaries(in root: Any, preferredKeys: [String]) -> [[String: Any]] {
        for key in preferredKeys {
            var matches: [Any] = []
            collectValues(named: key, in: root, into: &matches)
            let normalized = matches.flatMap(normalizeDocuments)
            if !normalized.isEmpty { return normalized }
        }
        return []
    }

    static func removingSensitiveValues(from value: Any) -> Any {
        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: [String: Any]()) { result, pair in
                result[pair.key] = sensitiveKeys.contains(pair.key)
                    ? "[REDACTED]"
                    : removingSensitiveValues(from: pair.value)
            }
        }
        if let array = value as? [Any] {
            return array.map(removingSensitiveValues)
        }
        return value
    }


    private static func collectValues(named key: String, in value: Any, into matches: inout [Any]) {
        if let dictionary = value as? [String: Any] {
            if let match = dictionary[key] { matches.append(match) }
            for child in dictionary.values { collectValues(named: key, in: child, into: &matches) }
        } else if let array = value as? [Any] {
            for child in array { collectValues(named: key, in: child, into: &matches) }
        }
    }

    private static func normalizeDocuments(_ value: Any) -> [[String: Any]] {
        if let array = value as? [Any] {
            return array.flatMap(normalizeDocuments)
        }
        guard let dictionary = value as? [String: Any] else { return [] }
        for wrapper in ["doc", "book"] {
            if let wrapped = dictionary[wrapper] {
                let normalized = normalizeDocuments(wrapped)
                if !normalized.isEmpty { return normalized }
            }
        }
        let fieldNames = Set(dictionary.keys)
        let known = Set(["bookname", "title", "authors", "author", "isbn13", "publisher", "bookImageURL"])
        return fieldNames.isDisjoint(with: known) ? [] : [dictionary]
    }
}
