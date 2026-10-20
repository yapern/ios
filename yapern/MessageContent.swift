import Foundation

/// Matches the website's link and media rules while preserving the original prose.
nonisolated enum MessageContent {
    struct Part: Hashable, Identifiable {
        let id: Int
        let text: String
        let url: URL?

        var imageURL: URL? {
            guard let url, ["png", "gif", "jpg", "webp"].contains(url.pathExtension.lowercased()) else { return nil }
            return url
        }

        var youtubeVideoID: String? {
            guard let url,
                  ["youtube.com", "www.youtube.com", "m.youtube.com"].contains(url.host?.lowercased() ?? ""),
                  url.path == "/watch",
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let id = components.queryItems?.first(where: { $0.name == "v" })?.value,
                  id.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil else { return nil }
            return id
        }
    }

    private static let links = try! NSRegularExpression(
        pattern: #"[a-z][a-z\d+.-]*://[^\s<>"'`“”‘’]+|(?:[\p{L}\p{N}](?:[\p{L}\p{N}-]*[\p{L}\p{N}])?\.)+[\p{L}]{2,63}(?![\p{L}\p{N}_-])(?::\d+)?(?:[/?#][^\s<>"'`“”‘’]*)?"#,
        options: [.caseInsensitive]
    )
    private static let precedingURLCharacter = try! NSRegularExpression(pattern: #"[\p{L}\p{N}_@./\\:+-]"#)

    static func parse(_ body: String) -> [Part] {
        let source = body as NSString
        var position = 0
        var parts: [Part] = []
        for match in links.matches(in: body, range: NSRange(location: 0, length: source.length)) {
            let start = match.range.location
            if start > 0 {
                let preceding = source.substring(with: source.rangeOfComposedCharacterSequence(at: start - 1))
                if precedingURLCharacter.firstMatch(in: preceding, range: NSRange(preceding.startIndex..., in: preceding)) != nil { continue }
            }
            let value = trimLink(source.substring(with: match.range))
            let destination = value.range(of: #"^[a-z][a-z\d+.-]*://"#, options: [.regularExpression, .caseInsensitive]) == nil
                ? "https://\(value)" : value
            guard var components = URLComponents(string: destination),
                  let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
                  let host = components.host, !host.isEmpty,
                  components.port.map({ (0...65535).contains($0) }) ?? true else { continue }
            components.scheme = scheme
            components.host = host.lowercased()
            guard let url = components.url else { continue }
            if start > position {
                parts.append(Part(id: parts.count, text: source.substring(with: NSRange(location: position, length: start - position)), url: nil))
            }
            parts.append(Part(id: parts.count, text: value, url: url))
            position = start + (value as NSString).length
        }
        if position < source.length {
            parts.append(Part(id: parts.count, text: source.substring(from: position), url: nil))
        }
        return parts
    }

    static func externalLinkURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme) else { return url }
        let isSiteOrigin = scheme == "https" && components.host?.lowercased() == "yapern.com"
            && (components.port == nil || components.port == 443)
        guard !isSiteOrigin,
              components.queryItems?.contains(where: { $0.name == "source" && $0.value == "yapern" }) != true else { return url }

        // Append without re-encoding existing query parameters; keep fragments last.
        let query = components.percentEncodedQuery ?? ""
        components.percentEncodedQuery = query.isEmpty ? "source=yapern" : "\(query)&source=yapern"
        return components.url ?? url
    }

    private static func trimLink(_ candidate: String) -> String {
        let brackets: [Character: Character] = [")": "(", "]": "[", "}": "{"]
        var value = candidate
        while let last = value.last {
            if ".,!?;:".contains(last) {
                value.removeLast()
            } else if let opening = brackets[last], value.filter({ $0 == last }).count > value.filter({ $0 == opening }).count {
                value.removeLast()
            } else {
                break
            }
        }
        return value
    }
}
