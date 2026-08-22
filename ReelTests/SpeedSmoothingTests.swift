import XCTest
@testable import Reel

/// 속도 스무딩 — #9 회귀 방어 (0.3초 스로틀과 이동평균).
@MainActor
final class SpeedSmoothingTests: XCTestCase {

    // MARK: - 파싱

    func testParseSpeedVariants() {
        // MiB/Mb → 10진 메가바이트 기준 (표시 재포맷과 단위 일관성 유지)
        XCTAssertEqual(QueueStore.parseSpeedBytesPerSec("5.2MiB/s") ?? 0, 5_200_000, accuracy: 1)
        XCTAssertEqual(QueueStore.parseSpeedBytesPerSec("5.2MB/s") ?? 0, 5_200_000, accuracy: 1)
        XCTAssertEqual(QueueStore.parseSpeedBytesPerSec("320KiB/s") ?? 0, 320_000, accuracy: 1)
        XCTAssertEqual(QueueStore.parseSpeedBytesPerSec("1.2GB/s") ?? 0, 1_200_000_000, accuracy: 100)
        // 공백 변형 (yt-dlp 일부 버전)
        XCTAssertEqual(QueueStore.parseSpeedBytesPerSec("5.2MiB /s") ?? 0, 5_200_000, accuracy: 1)
        // 파싱 불가 → nil
        XCTAssertNil(QueueStore.parseSpeedBytesPerSec(""))
        XCTAssertNil(QueueStore.parseSpeedBytesPerSec("Unknown"))
        XCTAssertNil(QueueStore.parseSpeedBytesPerSec("NA"))
    }

    // MARK: - 이동평균

    func testSmoothedSpeedAveragesSamples() {
        // 1000 B/s → 3000 B/s 두 샘플의 평균은 2000 B/s
        let (s1, w1) = QueueStore.smoothedSpeed("1000B/s", window: [])
        XCTAssertEqual(s1, "1 KB/s")
        let (s2, w2) = QueueStore.smoothedSpeed("3000B/s", window: w1)
        // 2샘플 평균 2000 B/s
        XCTAssertTrue(s2.contains("2 KB"), "평균 반영: \(s2)")
        XCTAssertEqual(w2.count, 2)
    }

    func testSmoothedSpeedWindowCapsAtFive() {
        var window: [Double] = []
        for i in 1...8 {
            let (_, w) = QueueStore.smoothedSpeed("\(i)000B/s", window: window)
            window = w
        }
        XCTAssertEqual(window.count, 5, "윈도우는 최대 5샘플")
        XCTAssertEqual(window.last ?? 0, 8_000, accuracy: 1, "최근 샘플 포함")
    }

    func testSmoothedSpeedDampensSpikes() {
        // 안정 흐름 후 스파이크가 와도 표시값이 즉시 최대치로 점프하지 않게
        var window: [Double] = []
        for _ in 0..<4 { let (_, w) = QueueStore.smoothedSpeed("1000B/s", window: window); window = w }
        let (smoothed, _) = QueueStore.smoothedSpeed("9000B/s", window: window)
        // 5샘플 평균 = (1000×4 + 9000)/5 = 2600 — "9 KB/s"가 아니라 완만한 값
        XCTAssertTrue(smoothed.contains("2.6 KB") || smoothed.contains("3 KB"),
                      "스파이크가 완화돼야 함: \(smoothed)")
        XCTAssertFalse(smoothed.contains("9 KB"), "스파이크 값이 그대로 나오면 안 됨")
    }

    func testSmoothedSpeedUnparseableReturnsRaw() {
        let (text, window) = QueueStore.smoothedSpeed("Unknown", window: [])
        XCTAssertEqual(text, "Unknown", "파싱 불가면 원문 유지")
        XCTAssertEqual(window.count, 0, "윈도우 오염 없음")
    }
}
