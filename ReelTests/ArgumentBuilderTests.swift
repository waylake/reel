import XCTest
@testable import Reel

/// ArgumentBuilder — UI 옵션 → yt-dlp CLI 인자 매핑의 계약.
/// 특히 playlistArgs는 #8(큰 채널 집계 버그)로 --dump-single-json → --print로 바뀐 경로.
final class ArgumentBuilderTests: XCTestCase {

    // MARK: - 단일 영상 메타데이터

    func testMetadataArgsUseNoPlaylist() {
        let args = ArgumentBuilder.metadataArgs(url: "https://youtu.be/ID")
        XCTAssertTrue(args.contains("--no-playlist"), "단일 메타데이터는 --no-playlist여야 함")
        XCTAssertTrue(args.contains("--ignore-config"))
        XCTAssertTrue(args.last == "https://youtu.be/ID")
    }

    // MARK: - 플레이리스트 열거 (#8 회귀 방어)

    func testPlaylistArgsUsePrintNotDumpJson() {
        let args = ArgumentBuilder.playlistArgs(url: "https://youtube.com/@handle")
        // 핵심: --dump-single-json은 큰 채널에서 entries가 잘렸다 (#8)
        XCTAssertFalse(args.contains("--dump-single-json"),
                       "--dump-single-json은 큰 플레이리스트에서 잘리므로 금지")
        // 줄 기반 --print + sentinel이어야 함
        let printIdx = args.firstIndex(of: "--print")
        XCTAssertNotNil(printIdx, "--print가 있어야 함")
        if let idx = printIdx, idx + 1 < args.count {
            let template = args[idx + 1]
            XCTAssertTrue(template.hasPrefix(ArgumentBuilder.sentinel),
                          "템플릿은 sentinel로 시작해야 파싱 가능")
            XCTAssertTrue(template.contains("%(id)s"))
            XCTAssertTrue(template.contains("%(url)s"))
            XCTAssertTrue(template.contains("%(title)s"))
        }
        XCTAssertTrue(args.contains("--flat-playlist"))
    }

    // MARK: - 다운로드 인자

    private func makeOptions(preset: Preset = .bestMP4,
                             playlistMode: PlaylistMode = .single) -> DownloadOptions {
        var o = DownloadOptions()
        o.preset = preset
        o.playlistMode = playlistMode
        o.outputDirectory = URL(fileURLWithPath: "/tmp")
        return o
    }

    func testDownloadArgsSingleMode() {
        let args = ArgumentBuilder.downloadArgs(url: "URL", options: makeOptions())
        XCTAssertTrue(args.contains("--no-playlist"))
        XCTAssertFalse(args.contains("--yes-playlist"))
    }

    func testDownloadArgsAllModeLimitsPlaylistItems() {
        var o = makeOptions(playlistMode: .all)
        o.maxPlaylistItems = 30
        let args = ArgumentBuilder.downloadArgs(url: "URL", options: o)
        XCTAssertTrue(args.contains("--yes-playlist"))
        // --playlist-items는 "1-N" 형식
        if let idx = args.firstIndex(of: "--playlist-items"), idx + 1 < args.count {
            XCTAssertEqual(args[idx + 1], "1-30")
        } else {
            XCTFail("--playlist-items 1-30이 있어야 함")
        }
    }

    func testDownloadArgsPresets() {
        // MP3 프리셋
        let mp3 = ArgumentBuilder.downloadArgs(url: "U", options: makeOptions(preset: .audioMP3))
        XCTAssertTrue(mp3.contains("-x"))
        if let idx = mp3.firstIndex(of: "--audio-format") { XCTAssertEqual(mp3[idx + 1], "mp3") }

        // 1080p 상한
        let hd = ArgumentBuilder.downloadArgs(url: "U", options: makeOptions(preset: .hd1080))
        if let idx = hd.firstIndex(of: "-f") {
            XCTAssertTrue(hd[idx + 1].contains("height<=1080"))
        } else {
            XCTFail("-f 인자가 있어야 함")
        }

        // 원본은 리먹스 없음
        let raw = ArgumentBuilder.downloadArgs(url: "U", options: makeOptions(preset: .original))
        XCTAssertFalse(raw.contains("--merge-output-format"))
    }

    func testProgressTemplateUsesSentinel() {
        let args = ArgumentBuilder.downloadArgs(url: "U", options: makeOptions())
        // sentinel 템플릿이 있어야 ProgressParser가 진행률을 인식
        let hasTemplate = args.contains(where: {
            $0.contains("download:\(ArgumentBuilder.sentinel)")
        })
        XCTAssertTrue(hasTemplate, "progress-template가 sentinel을 포함해야 함")
    }
}
