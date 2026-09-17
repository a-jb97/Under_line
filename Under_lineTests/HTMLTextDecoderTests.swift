import XCTest
@testable import Under_line

@MainActor
final class HTMLTextDecoderTests: XCTestCase {
    func test_plainKorean_returnsWithoutFallback() {
        var fallbackCount = 0
        let value = HTMLTextDecoder.decode("어린 왕자") { _ in
            fallbackCount += 1
            return "fallback"
        }
        XCTAssertEqual(value, "어린 왕자")
        XCTAssertEqual(fallbackCount, 0)
    }

    func test_supportedNamedEntities_decodeInOnePass() {
        let value = HTMLTextDecoder.decode("A&amp;B &lt;책&gt; &quot;문장&quot; &apos;인용&apos;&nbsp;끝")
        XCTAssertEqual(value, "A&B <책> \"문장\" '인용'\u{00A0}끝")
    }

    func test_decimalAndHexReferences_decodeValidUnicodeScalars() {
        XCTAssertEqual(HTMLTextDecoder.decode("&#44032; &#xAC00; &#X1F4DA;"), "가 가 📚")
    }

    func test_nestedEncoding_decodesOnlyOnce() {
        XCTAssertEqual(HTMLTextDecoder.decode("&amp;amp; &amp;lt;"), "&amp; &lt;")
    }

    func test_malformedReferences_remainUnchangedWithoutFallback() {
        let input = "A &amp B &#; &#xZZ; &#55296; &;"
        var fallbackCount = 0
        let value = HTMLTextDecoder.decode(input) { _ in
            fallbackCount += 1
            return "fallback"
        }
        XCTAssertEqual(value, input)
        XCTAssertEqual(fallbackCount, 0)
    }

    func test_actualHTML_usesLegacyParser() {
        var fallbackCount = 0
        let value = HTMLTextDecoder.decode("<b>굵은 제목</b>") { text in
            fallbackCount += 1
            return HTMLTextDecoder.legacyDecode(text)
        }
        XCTAssertEqual(value, "굵은 제목")
        XCTAssertEqual(fallbackCount, 1)
    }

    func test_unsupportedNamedEntity_usesLegacyParser() {
        var fallbackCount = 0
        let value = HTMLTextDecoder.decode("저작권 &copy; 출판사") { text in
            fallbackCount += 1
            return HTMLTextDecoder.legacyDecode(text)
        }
        XCTAssertEqual(value, "저작권 © 출판사")
        XCTAssertEqual(fallbackCount, 1)
    }

    func test_angleBracketsInPlainText_doNotUseFallback() {
        var fallbackCount = 0
        let value = HTMLTextDecoder.decode("1 < 2 > 0") { _ in
            fallbackCount += 1
            return "fallback"
        }
        XCTAssertEqual(value, "1 < 2 > 0")
        XCTAssertEqual(fallbackCount, 0)
    }

    func test_nonASCIIAngleBrackets_doNotLookLikeHTMLTags() {
        var fallbackCount = 0
        let value = HTMLTextDecoder.decode("<책>") { _ in
            fallbackCount += 1
            return "fallback"
        }
        XCTAssertEqual(value, "<책>")
        XCTAssertEqual(fallbackCount, 0)
    }

    func test_toDomain_decodesTitleAndDescriptionWithoutChangingOtherFields() throws {
        let json = #"""
        {
          "title": "어린 왕자 &amp; 여우",
          "author": "생텍쥐페리",
          "isbn13": "9780000000000",
          "cover": "https://example.com/cover.jpg",
          "publisher": "테스트 출판사",
          "pubDate": "2026-09-17",
          "categoryName": "국내도서>소설",
          "bestRank": 1,
          "description": "중요한 것은 &quot;눈&quot;에 보이지 않아"
        }
        """#.data(using: .utf8)!
        let item = try JSONDecoder().decode(AladinBookItem.self, from: json)
        let book = item.toDomain()
        XCTAssertEqual(book.title, "어린 왕자 & 여우")
        XCTAssertEqual(book.description, "중요한 것은 \"눈\"에 보이지 않아")
        XCTAssertEqual(book.author, "생텍쥐페리")
        XCTAssertEqual(book.isbn13, "9780000000000")
        XCTAssertEqual(book.category, "소설")
        XCTAssertEqual(book.bestRank, 1)
    }

    func test_fastPathBenchmark_comparesSameInputWithLegacyParser() {
        let sample = "어린 왕자 &amp; 여우 &#x1F4DA; &quot;중요한 것은 눈에 보이지 않아&quot;"
        let iterations = 100
        let fastStart = ProcessInfo.processInfo.systemUptime
        for _ in 0..<iterations { _ = HTMLTextDecoder.decode(sample) }
        let fastDuration = ProcessInfo.processInfo.systemUptime - fastStart

        let legacyStart = ProcessInfo.processInfo.systemUptime
        for _ in 0..<iterations { _ = HTMLTextDecoder.legacyDecode(sample) }
        let legacyDuration = ProcessInfo.processInfo.systemUptime - legacyStart

        print("HTMLTextDecoder benchmark iterations=\(iterations) fastMs=\(fastDuration * 1_000) legacyMs=\(legacyDuration * 1_000)")
        XCTAssertLessThan(fastDuration, legacyDuration)
    }
}
