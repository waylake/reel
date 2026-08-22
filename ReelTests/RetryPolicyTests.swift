import XCTest
@testable import Reel

/// 재시도 정책 회귀 방어 — #11 (봇 감지 오류가 재시도 없이 즉시 실패하던 버그).
///
/// yt-dlp 공식 문서/이슈 분류 기준은 docs/ytdlp-notes.md 참조.
@MainActor
final class RetryPolicyTests: XCTestCase {

    // MARK: - 봇 감지 계열 → 재시도해야 함 (#11의 핵심)

    func testPageNeedsToBeReloadedIsRetryable() {
        // 실제 사용자 제보 오류 (2026-08-22, watch?v=VZEbsrwfGXI)
        XCTAssertTrue(QueueStore.isRetryableError(
            "[youtube] VZEbsrwfGXI: The page needs to be reloaded."))
    }

    func testHTTP403IsRetryable() {
        XCTAssertTrue(QueueStore.isRetryableError(
            "ERROR: unable to download video data: HTTP Error 403: Forbidden"))
        XCTAssertTrue(QueueStore.isRetryableError("HTTP Error 403"))
    }

    func testUnableToExtractIsRetryable() {
        XCTAssertTrue(QueueStore.isRetryableError("ERROR: unable to extract video data"))
        XCTAssertTrue(QueueStore.isRetryableError(
            "ERROR: unable to download video data: HTTP Error 403: Forbidden"))
    }

    func testPlayabilityStatusIsRetryable() {
        XCTAssertTrue(QueueStore.isRetryableError(
            "tv_downgraded player response playability status: UNPLAYABLE"))
    }

    // MARK: - 기존 일시적 오류 → 계속 재시도

    func testTransientNetworkErrorsAreRetryable() {
        XCTAssertTrue(QueueStore.isRetryableError("HTTP Error 429: Too Many Requests"))
        XCTAssertTrue(QueueStore.isRetryableError("connection reset by peer"))
        XCTAssertTrue(QueueStore.isRetryableError("timed out"))
    }

    // MARK: - 영구 실패 → 재시도하면 안 됨

    func testAgeRestrictedIsNotRetryable() {
        XCTAssertFalse(QueueStore.isRetryableError("This video is age-restricted"))
    }

    func testSignInToConfirmIsNotRetryable() {
        // IP 기반 봇 판정 — 재시도로 안 풀림 (docs/ytdlp-notes.md §1)
        XCTAssertFalse(QueueStore.isRetryableError(
            "Sign in to confirm you're not a bot"))
    }

    func testPrivateVideoIsNotRetryable() {
        XCTAssertFalse(QueueStore.isRetryableError("Private video. Sign in if you've been granted access"))
    }

    // MARK: - 봇 감지 판별 (자동 업데이트 트리거)

    func testIsYouTubeBlockError() {
        XCTAssertTrue(QueueStore.isYouTubeBlockError("The page needs to be reloaded"))
        XCTAssertTrue(QueueStore.isYouTubeBlockError("HTTP Error 403: Forbidden"))
        XCTAssertTrue(QueueStore.isYouTubeBlockError("Sign in to confirm you're not a bot"))
        XCTAssertFalse(QueueStore.isYouTubeBlockError("connection timed out"))
        XCTAssertFalse(QueueStore.isYouTubeBlockError("age-restricted"))
    }
}
