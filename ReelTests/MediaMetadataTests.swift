import XCTest
@testable import Reel

/// MediaMetadata — #8 회귀 방어: --print 줄 기반 플레이리스트 파싱.
final class MediaMetadataTests: XCTestCase {

    private let s = ArgumentBuilder.sentinel

    // MARK: - 단일 영상 JSON (--dump-single-json --no-playlist)

    func testSingleVideoJSON() throws {
        let json = """
        {"title": "테스트 영상", "duration": 213.5, "thumbnail": "https://example.com/t.jpg",
         "width": 1920, "height": 1080, "vcodec": "avc1.640028",
         "filesize_approx": 12345678, "uploader": "업로더"}
        """
        let meta = try XCTUnwrap(MediaMetadata(jsonData: Data(json.utf8)))
        XCTAssertEqual(meta.title, "테스트 영상")
        XCTAssertEqual(meta.durationSeconds, 213.5)
        XCTAssertEqual(meta.height, 1080)
        XCTAssertNotNil(meta.thumbnailURL)
    }

    // MARK: - 플레이리스트 줄 파싱 (#8: --print 형식)

    private func playlistData(_ lines: [String]) -> Data {
        lines.joined(separator: "\n").data(using: .utf8)!
    }

    func testMultiEntryParsing() throws {
        let data = playlistData([
            "\(s)|id1|https://youtube.com/watch?v=id1|2664.0|NA|첫 번째 영상",
            "\(s)|id2|https://youtube.com/watch?v=id2|1184.0|NA|두 번째 영상",
            "\(s)|id3|https://youtube.com/watch?v=id3|NA|NA|세 번째 영상",
        ])
        let info = try XCTUnwrap(MediaMetadata.playlistInfo(from: data))
        XCTAssertTrue(info.isPlaylist, "항목 2개 이상은 플레이리스트")
        XCTAssertEqual(info.entries.count, 3)
        XCTAssertEqual(info.count, 3)
        XCTAssertEqual(info.entries[0].url, "https://youtube.com/watch?v=id1")
        XCTAssertEqual(info.entries[0].title, "첫 번째 영상")
        XCTAssertEqual(info.entries[0].durationSeconds, 2664.0)
        XCTAssertNil(info.entries[2].durationSeconds, "NA duration은 nil")
    }

    func testPipeInTitleIsPreserved() throws {
        // 제목에 파이프가 있어도 마지막 필드라 잘려선 안 됨 (#8 설계)
        let data = playlistData([
            "\(s)|id1|https://youtu.be/id1|100.0|채널명|제목에 | 파이프가 있어요",
        ])
        let info = try XCTUnwrap(MediaMetadata.playlistInfo(from: data))
        XCTAssertEqual(info.entries[0].title, "제목에 | 파이프가 있어요")
        XCTAssertEqual(info.channelName, "채널명", "uploader 첫 유효값이 채널명")
    }

    func testSingleEntryIsNotPlaylist() throws {
        let data = playlistData([
            "\(s)|id1|https://youtu.be/id1|100.0|NA|단일 영상",
        ])
        let info = try XCTUnwrap(MediaMetadata.playlistInfo(from: data))
        XCTAssertFalse(info.isPlaylist, "항목 1개는 단일 영상")
        XCTAssertEqual(info.entries.count, 1)
    }

    func testLargePlaylistIsNotTruncated() throws {
        // #8 시나리오: 752개 항목이 전부 파싱되는지 (819개 채널 → 3개만 나오던 버그)
        let lines = (1...752).map { "\(s)|id\($0)|https://youtu.be/id\($0)|60.0|NA|영상 \($0)" }
        let info = try XCTUnwrap(MediaMetadata.playlistInfo(from: playlistData(lines)))
        XCTAssertEqual(info.entries.count, 752, "큰 플레이리스트가 잘리면 안 됨")
        XCTAssertEqual(info.entries.last?.title, "영상 752")
    }

    func testEmptyAndNoiseInput() {
        // 빈 데이터/잡음 줄은 항목 없는 결과 (nil이 아니어도 무방 — 호출부가 entries로 분기)
        let empty = MediaMetadata.playlistInfo(from: Data())
        XCTAssertEqual(empty?.entries.count ?? -1, 0, "빈 데이터는 항목 0")
        let noise = playlistData(["[youtube] Extracting URL: ...", "garbage"])
        let info = MediaMetadata.playlistInfo(from: noise)
        XCTAssertEqual(info?.entries.count ?? -1, 0, "sentinel 없는 줄은 무시")
        XCTAssertEqual(info?.isPlaylist, false)
    }

    func testKoreanChannelURL() throws {
        // @원빅월드쇼 재현 시나리오 — percent-encoded URL과 한글 제목
        let data = playlistData([
            "\(s)|Iiwdpi1WvDI|https://www.youtube.com/watch?v=Iiwdpi1WvDI|2664.0|NA|트럼프는 왜 자꾸 부정선거를 주장할까?",
            "\(s)|fMi9PvIz8XI|https://www.youtube.com/watch?v=fMi9PvIz8XI|1184.0|NA|미국 총선 D-데이",
        ])
        let info = try XCTUnwrap(MediaMetadata.playlistInfo(from: data))
        XCTAssertTrue(info.isPlaylist)
        XCTAssertEqual(info.entries.count, 2)
        XCTAssertTrue(info.entries[0].title.contains("트럼프"))
    }
}
