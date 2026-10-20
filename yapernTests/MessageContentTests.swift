import XCTest
@testable import yapern

final class MessageContentTests: XCTestCase {
    func testPreservesUnicodeWhitespaceAndBalancedPunctuation() {
        let body = "👋 See (HTTPS://example.com/wiki/Function_(mathematics)).\n\n  café.fr and www.example.org/path?q=one!"
        let parts = MessageContent.parse(body)
        XCTAssertEqual(parts.map(\.text).joined(), body)
        XCTAssertEqual(parts.compactMap(\.url).map(\.absoluteString), [
            "https://example.com/wiki/Function_(mathematics)",
            "https://xn--caf-dma.fr", "https://www.example.org/path?q=one",
        ])
    }

    func testRejectsUnsafeSchemesEmailsPathsAndInvalidPorts() {
        for body in [
            "javascript:alert(1)", "javascript://example.com/a", "ftp://example.com/a",
            "file:///example.com/path", "mailto:hello@example.com", "hello@example.com",
            "/example.com/path", "https://", "https://?query", "https://example.com:99999",
            "1.2.3", "No links here!", "",
        ] {
            let parts = MessageContent.parse(body)
            XCTAssertEqual(parts.map(\.text).joined(), body)
            XCTAssertTrue(parts.allSatisfy { $0.url == nil }, body)
        }
    }

    func testOnlyDirectSupportedImagesBecomeMedia() {
        let body = "Before https://files.example/a/photo.PNG?size=640#image, then cdn.example/photo.webp after."
        let parts = MessageContent.parse(body)
        XCTAssertEqual(parts.map(\.text).joined(), body)
        XCTAssertEqual(parts.compactMap(\.imageURL).map(\.absoluteString), [
            "https://files.example/a/photo.PNG?size=640#image", "https://cdn.example/photo.webp",
        ])
        for body in ["https://example.com/photo.png.html", "https://example.com/photo.jpg/path", "https://example.com/page?file=photo.png"] {
            XCTAssertTrue(MessageContent.parse(body).allSatisfy { $0.imageURL == nil })
        }
    }

    func testExtensionlessPreviewFirstLineAndJPEGImages() {
        let body = "https://cdn.example.com/preview?id=123\nhttps://example.com/article\n\nAn article"
        let parts = MessageContent.parse(body)
        XCTAssertEqual(parts.map(\.text).joined(), body)
        XCTAssertEqual(parts.first?.imageURL?.host, "cdn.example.com")
        XCTAssertNil(parts.first(where: { $0.url?.host == "example.com" })?.imageURL)
        XCTAssertNotNil(MessageContent.parse("https://example.com/photo.jpeg").first?.imageURL)
    }

    func testYouTubeWatchLinksRequireExactHostAndValidID() {
        XCTAssertEqual(MessageContent.parse("youtube.com/watch?v=issziaa-dtY&t=45s").first?.youtubeVideoID, "issziaa-dtY")
        for body in [
            "https://youtube.com.evil.example/watch?v=issziaa-dtY",
            "https://evil-youtube.com/watch?v=issziaa-dtY",
            "https://youtube.com/watch?v=too-short", "https://youtube.com/watch?t=45s",
        ] {
            XCTAssertTrue(MessageContent.parse(body).allSatisfy { $0.youtubeVideoID == nil }, body)
        }
    }

    func testExternalLinksAppendSourceBeforeFragmentsWithoutReencodingQueries() throws {
        let cases = [
            ("https://example.com/page", "https://example.com/page?source=yapern"),
            ("http://example.com/page#section", "http://example.com/page?source=yapern#section"),
            ("https://example.com/page?", "https://example.com/page?source=yapern"),
            ("https://example.com/page?x=1#section", "https://example.com/page?x=1&source=yapern#section"),
            ("https://example.com/page?q=a%20b&x=~&token=a%2Fb%2bc#section",
             "https://example.com/page?q=a%20b&x=~&token=a%2Fb%2bc&source=yapern#section"),
            ("https://example.com/page?source=other", "https://example.com/page?source=other&source=yapern"),
        ]
        for (input, expected) in cases {
            let url = try XCTUnwrap(URL(string: input))
            let destination = MessageContent.externalLinkURL(url)
            XCTAssertEqual(destination.absoluteString, expected, input)
            XCTAssertEqual(MessageContent.externalLinkURL(destination), destination, input)
        }
    }

    func testExternalLinksKeepSiteLinksExistingSourceAndOtherSchemesUnchanged() throws {
        for input in [
            "https://yapern.com/y/general/message?x=1#replies",
            "https://YAPERN.com:443/y/general",
            "https://example.com/page?source=yapern#section",
            "https://example.com/page?source=other&source=yapern",
            "https://example.com/page?%73ource=%79apern",
            "mailto:person@example.com", "ftp://example.com/file",
        ] {
            let url = try XCTUnwrap(URL(string: input))
            XCTAssertEqual(MessageContent.externalLinkURL(url), url, input)
        }

        for input in [
            "http://yapern.com/page", "https://yapern.com:8443/page",
            "https://www.yapern.com/page", "https://yapern.com.example.org/page",
        ] {
            let url = try XCTUnwrap(URL(string: input))
            XCTAssertEqual(MessageContent.externalLinkURL(url).absoluteString, "\(input)?source=yapern", input)
        }
    }
}
