import Foundation

/// 저장된 표지 URL은 유지하고 책장에서만 원본 후보를 선택한다.
enum ShelfCoverImageSource {
    static func originalURL(for thumbnailURL: URL) -> URL? {
        guard let host = thumbnailURL.host?.lowercased(), host.hasSuffix(".kakaocdn.net"),
              thumbnailURL.path.hasPrefix("/thumb/"),
              let thumbnail = URLComponents(url: thumbnailURL, resolvingAgainstBaseURL: false),
              let source = thumbnail.queryItems?.first(where: { $0.name == "fname" })?.value,
              var original = URLComponents(string: source),
              let scheme = original.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let originalHost = original.host, !originalHost.isEmpty else { return nil }

        // 카카오 예제의 원본 주소는 HTTP이지만 HTTPS로도 제공된다.
        // HTTPS 원본에 접근할 수 없으면 호출부가 기존 썸네일로 돌아간다.
        original.scheme = "https"
        guard let url = original.url, url != thumbnailURL else { return nil }
        return url
    }
}
