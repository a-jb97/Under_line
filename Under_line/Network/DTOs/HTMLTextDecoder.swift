import UIKit

/// 알라딘 응답의 HTML 문자 참조를 일반 문자열로 바꾼다.
/// 단순 문자열은 가볍게 처리하고 실제 HTML은 기존 Foundation 파서에 맡긴다.
@MainActor
enum HTMLTextDecoder {
    private enum FastResult {
        case decoded(String)
        case needsHTMLParser
    }

    static func decode(_ text: String) -> String {
        decode(text, htmlFallback: legacyDecode)
    }

    static func decode(
        _ text: String,
        htmlFallback: (String) -> String
    ) -> String {
        guard text.contains("&") || containsHTMLTag(in: text) else { return text }
        switch fastDecode(text) {
        case .decoded(let decoded):
            return decoded
        case .needsHTMLParser:
            return htmlFallback(text)
        }
    }

    static func legacyDecode(_ text: String) -> String {
        let data = Data(text.utf8)
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ]
        return (try? NSAttributedString(data: data, options: options, documentAttributes: nil))?
            .string ?? text
    }

    private static func fastDecode(_ text: String) -> FastResult {
        guard !containsHTMLTag(in: text) else { return .needsHTMLParser }
        guard text.contains("&") else { return .decoded(text) }

        var result = ""
        result.reserveCapacity(text.utf8.count)
        var cursor = text.startIndex

        while let ampersand = text[cursor...].firstIndex(of: "&") {
            result.append(contentsOf: text[cursor..<ampersand])
            guard let semicolon = entityTerminator(in: text, after: ampersand) else {
                result.append("&")
                cursor = text.index(after: ampersand)
                continue
            }

            let bodyStart = text.index(after: ampersand)
            let body = text[bodyStart..<semicolon]
            if let scalar = scalar(for: body) {
                result.unicodeScalars.append(scalar)
                cursor = text.index(after: semicolon)
            } else if isUnsupportedNamedEntity(body) {
                return .needsHTMLParser
            } else {
                result.append(contentsOf: text[ampersand...semicolon])
                cursor = text.index(after: semicolon)
            }
        }

        result.append(contentsOf: text[cursor...])
        return .decoded(result)
    }

    private static func entityTerminator(in text: String, after ampersand: String.Index) -> String.Index? {
        var index = text.index(after: ampersand)
        // 지원 엔티티와 유효한 Unicode 숫자 참조에 충분하며 비정상 장문 검색을 제한한다.
        for _ in 0..<32 where index < text.endIndex {
            if text[index] == ";" { return index }
            if text[index] == "&" || text[index].isWhitespace { return nil }
            index = text.index(after: index)
        }
        return nil
    }

    private static func scalar(for body: Substring) -> Unicode.Scalar? {
        switch body {
        case "amp": return "&"
        case "lt": return "<"
        case "gt": return ">"
        case "quot": return "\""
        case "apos": return "'"
        case "nbsp": return "\u{00A0}"
        default: break
        }

        let digits: Substring
        let radix: Int
        if body.hasPrefix("#x") || body.hasPrefix("#X") {
            digits = body.dropFirst(2)
            radix = 16
        } else if body.hasPrefix("#") {
            digits = body.dropFirst()
            radix = 10
        } else {
            return nil
        }
        guard !digits.isEmpty, let value = UInt32(digits, radix: radix) else { return nil }
        return Unicode.Scalar(value)
    }

    private static func isUnsupportedNamedEntity(_ body: Substring) -> Bool {
        guard let first = body.first, first.isASCII, first.isLetter else { return false }
        return body.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    private static func containsHTMLTag(in text: String) -> Bool {
        var cursor = text.startIndex
        while let opening = text[cursor...].firstIndex(of: "<") {
            let next = text.index(after: opening)
            guard next < text.endIndex else { return false }
            let marker = text[next]
            let looksLikeTag: Bool
            if marker == "/" {
                let nameStart = text.index(after: next)
                looksLikeTag = nameStart < text.endIndex
                    && text[nameStart].isASCII
                    && text[nameStart].isLetter
            } else {
                looksLikeTag = (marker.isASCII && marker.isLetter) || marker == "!" || marker == "?"
            }
            if looksLikeTag, text[next...].contains(">") { return true }
            cursor = next
        }
        return false
    }
}
