import XCTest
@testable import Reel

/// MediaLink — URL 형태만으로 채널/플레이리스트/단일 영상을 분류. (#10)
final class MediaLinkTests: XCTestCase {

    // MARK: - 채널

    func testHandleChannelURLs() {
        for url in [
            "https://www.youtube.com/@원빅월드쇼",
            "https://www.youtube.com/@%EC%9B%90%EB%B9%85%EC%9B%94%EB%93%9C%EC%87%BC",
            "https://www.youtube.com/@handle/videos",
            "https://youtube.com/channel/UCxxxxxxxx",
            "https://m.youtube.com/@somebody",
        ] {
            let link = MediaLink(url)
            XCTAssertEqual(link?.kind, .channel, "채널이어야 함: \(url)")
        }
    }

    // MARK: - 플레이리스트

    func testPlaylistURLs() {
        for url in [
            "https://www.youtube.com/playlist?list=PLxxxx",
            "https://www.youtube.com/watch?v=abc&list=PLxxxx",
            "https://youtu.be/abc?list=PLxxxx",
        ] {
            XCTAssertEqual(MediaLink(url)?.kind, .playlist, "플레이리스트여야 함: \(url)")
        }
    }

    // MARK: - 단일 영상

    func testSingleVideoURLs() {
        for url in [
            "https://www.youtube.com/watch?v=abc",
            "https://youtu.be/abc",
            "https://www.youtube.com/shorts/abc",
        ] {
            XCTAssertEqual(MediaLink(url)?.kind, .single, "단일 영상이어야 함: \(url)")
        }
    }

    // MARK: - 기타

    func testNonMediaInputIsRejected() {
        XCTAssertNil(MediaLink("not a url"))
        XCTAssertNil(MediaLink("ftp://example.com/x"))
        XCTAssertNil(MediaLink(""))
    }

    func testOtherSites() {
        // yt-dlp 지원 사이트는 경로가 있으면 허용
        XCTAssertEqual(MediaLink("https://vimeo.com/12345")?.kind, .other)
    }
}
