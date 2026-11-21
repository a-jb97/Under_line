import Foundation
import Kingfisher

/// 책장과 도서 상세에서 원본 표지를 우선 요청하고, 실패하면 저장된 표지 URL을 사용한다.
enum ShelfCoverImageSource {
    static func request(for coverURL: URL) -> (url: URL, options: KingfisherOptionsInfo) {
        guard let originalURL = originalURL(for: coverURL) else { return (coverURL, []) }
        return (originalURL, [.alternativeSources([.network(KF.ImageResource(downloadURL: coverURL))])])
    }

    private static func originalURL(for thumbnailURL: URL) -> URL? {
        guard let host = thumbnailURL.host?.lowercased(), host.hasSuffix(".kakaocdn.net"),
              thumbnailURL.path.hasPrefix("/thumb/"),
              let thumbnail = URLComponents(url: thumbnailURL, resolvingAgainstBaseURL: false),
              let source = thumbnail.queryItems?.first(where: { $0.name == "fname" })?.value,
              var original = URLComponents(string: source),
              let scheme = original.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let originalHost = original.host, !originalHost.isEmpty else { return nil }

        // 카카오 예제의 원본 주소는 HTTP이지만 HTTPS로도 제공된다.
        original.scheme = "https"
        guard let url = original.url, url != thumbnailURL else { return nil }
        return url
    }
}
