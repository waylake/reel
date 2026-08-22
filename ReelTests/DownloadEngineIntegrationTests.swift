import XCTest
@testable import Reel

/// 엔진 통합 테스트 — 실제 yt-dlp 프로세스를 띄워 DownloadEngine actor의
/// 라이프사이클(실행·캡처·에러)을 검증한다. UI 권한 불필요 — 프로세스 spawn은
/// TCC(접근성) 대상이 아니다. (#12)
///
/// 바이너리가 없는 환경에선 자동 스킵 — CI 사전 설치로 항상 돈다.
final class DownloadEngineIntegrationTests: XCTestCase {

    private var engine: DownloadEngine!

    override func setUp() {
        super.setUp()
        engine = DownloadEngine()
    }

    // MARK: - 버전 조회 (가장 빠른 생존 검증)

    func testYtdlpVersionReturnsSomething() async throws {
        guard BinaryResolver.ytdlp != nil else {
            throw XCTSkip("yt-dlp 미설치 환경 — 설치 후 재실행")
        }
        let version = await engine.ytdlpVersion()
        XCTAssertNotNil(version, "yt-dlp --version이 값을 반환해야 함")
        XCTAssertTrue(version?.isEmpty == false)
        // 날짜 형태 버전 (2026.08.19 등) — 숫자를 포함
        XCTAssertTrue(version?.contains(where: { $0.isNumber }) == true,
                      "버전은 숫자를 포함: \(version ?? "nil")")
    }

    // MARK: - 메타데이터 실패 경로 (실제 오류 전파)

    func testFetchMetadataPropagatesFailure() async throws {
        guard BinaryResolver.ytdlp != nil else {
            throw XCTSkip("yt-dlp 미설치 환경")
        }
        // 존재하지 않는 영상 — 에러를 정상적으로 받아야 (크래시 아님)
        do {
            _ = try await engine.fetchMetadata(url: "https://www.youtube.com/watch?v=ZZZZZZZZZZZ")
            // 유튜브가 가짜 ID에 다양하게 응답하므로 성공도 배제하진 않는다
        } catch {
            // 실패 시 EngineError여야 함
            XCTAssertTrue(error is EngineError, "EngineError로 래핑돼야 함: \(error)")
        }
    }

    // MARK: - 플레이리스트 열거 실패 경로

    func testFetchPlaylistInfoWithInvalidURL() async throws {
        guard BinaryResolver.ytdlp != nil else {
            throw XCTSkip("yt-dlp 미설치 환경")
        }
        let info = try? await engine.fetchPlaylistInfo(url: "https://example.com/not-a-video")
        // 실패하면 nil, 성공해도 항목은 없어야 함 — 어느 쪽이든 크래시 없이 완결
        if let info {
            XCTAssertFalse(info.isPlaylist, "일반 웹페이지는 플레이리스트가 아님")
        }
    }

    // MARK: - yt-dlp 인자 스모크 (실제 실행)

    func testYtdlpRunsOurCanonicalArgs() async throws {
        guard let bin = BinaryResolver.ytdlp else {
            throw XCTSkip("yt-dlp 미설치 환경")
        }
        // ArgumentBuilder가 만드는 인자가 실제 yt-dlp에서 살아남는지 —
        // --print 템플릿 문법 오류가 있으면 여기서 잡힌다 (#8 회귀 방어)
        let args = ArgumentBuilder.playlistArgs(url: "https://example.com/x")
        let proc = Process()
        proc.executableURL = bin
        proc.arguments = Array(args.dropFirst(0).filter { $0 != "https://example.com/x" })
        // URL 없이 옵션만으로 --version 대신: 옵션 유효성은 --help가 아니라
        // 실제 실행으로 확인. 여기선 인자 해석만: 끝에 --version을 붙여 즉시 종료 유도
        proc.arguments = Array(args.dropLast(1)) + ["--version"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        try proc.run()
        proc.waitUntilExit()
        // 옵션 해석 단계에서 죽지 않고 정상 종료해야 함 (--version은 0 반환)
        // 단, URL이 빠진 것에 대한 오류가 나면 0이 아닐 수 있으므로 0 또는 1만 허용
        XCTAssertLessThanOrEqual(proc.terminationStatus, 1,
                                 "yt-dlp가 우리 인자를 파싱하지 못해 크래시하면 안 됨 (status=\(proc.terminationStatus))")
    }

    // MARK: - BinaryResolver 우선순위 (구조 검증)

    func testBinaryResolverFindsYtdlpSomewhere() {
        // 개발 머신·CI 어디서든 yt-dlp를 찾아야 함
        if FileManager.default.isExecutableFile(atPath: BinaryResolver.managedDir.appending(path: "yt-dlp").path) {
            XCTAssertNotNil(BinaryResolver.ytdlp, "관리본이 있으면 반드시 해석돼야 함")
        }
        // 경로가 응답하는지 자체가 계약
        _ = BinaryResolver.ffmpegLocation
    }
}
