import XCTest
@testable import Reel

/// ProgressParser — yt-dlp stdout 한 줄 → EngineEvent 변환의 계약.
final class ProgressParserTests: XCTestCase {

    private let s = ArgumentBuilder.sentinel

    // MARK: - 진행률 라인 (sentinel + progress-template)

    func testProgressLineParsesAllFields() {
        let line = "\(s) 42.5%|  5.2MiB/s|01:23| 4430233|10421706"
        let events = ProgressParser.parse(line: line)
        guard case .progress(let fraction, let speed, let eta, let downloaded, let total)? = events.first else {
            return XCTFail("progress 이벤트가 나와야 함: \(events)")
        }
        XCTAssertEqual(fraction, 0.425, accuracy: 0.001)
        XCTAssertEqual(speed, "5.2MiB/s")
        XCTAssertEqual(eta, "01:23")
        XCTAssertEqual(downloaded, 4_430_233)
        XCTAssertEqual(total, 10_421_706)
    }

    func testProgressLineWithUnknowns() {
        // 속도/ETA/total을 모를 때 "Unknown"/"NA" → 빈 문자열/nil
        let line = "\(s) 10.0%|Unknown B/s|Unknown| 1024|NA"
        let events = ProgressParser.parse(line: line)
        guard case .progress(let fraction, let speed, let eta, _, let total)? = events.first else {
            return XCTFail("progress 이벤트가 나와야 함")
        }
        XCTAssertEqual(fraction, 0.1, accuracy: 0.001)
        XCTAssertEqual(speed, "")
        XCTAssertEqual(eta, "")
        XCTAssertNil(total)
    }

    func testProgressClampsOutOfRangePercent() {
        XCTAssertEqual(ProgressParser.parse(line: "\(s) 150%|x|y|1|2").first,
                       .progress(fraction: 1.0, speed: "x", eta: "y", downloaded: 1, total: 2))
        XCTAssertEqual(ProgressParser.parse(line: "\(s) -5%|x|y|1|2").first,
                       .progress(fraction: 0.0, speed: "x", eta: "y", downloaded: 1, total: 2))
    }

    // MARK: - 최종 파일 라인

    func testFinalFileLine() {
        XCTAssertEqual(ProgressParser.parse(line: "\(s)FILE|/tmp/영상.mp4"),
                       [.finalFile("/tmp/영상.mp4")])
        // NA·빈 경로는 이벤트 없음
        XCTAssertEqual(ProgressParser.parse(line: "\(s)FILE|NA"), [])
        XCTAssertEqual(ProgressParser.parse(line: "\(s)FILE|"), [])
    }

    // MARK: - 후처리(인코딩) 마커

    func testPostprocessingMarkersEmitEncodingPhase() {
        for marker in ["[Merger]", "[VideoConvertor]", "[ExtractAudio]",
                       "[VideoRemuxer]", "[Metadata]", "[EmbedSubtitle]", "[SponsorBlock]"] {
            let events = ProgressParser.parse(line: "Deleting original file \(marker) args")
            XCTAssertEqual(events, [.phase(.encoding)], "마커 \(marker)는 encoding 단계여야 함")
        }
    }

    // MARK: - Destination

    func testDestinationLine() {
        XCTAssertEqual(ProgressParser.parse(line: "[download] Destination: /tmp/a.mp4"),
                       [.destination("/tmp/a.mp4")])
    }

    // MARK: - 잡음

    func testNoiseLinesProduceNothing() {
        XCTAssertEqual(ProgressParser.parse(line: ""), [])
        XCTAssertEqual(ProgressParser.parse(line: "[youtube] Extracting URL: https://..."), [])
        XCTAssertEqual(ProgressParser.parse(line: "garbage without markers"), [])
    }
}
