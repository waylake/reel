import Testing
import SwiftUI
@testable import Reel

/// 호스팅 뷰 테스트 — Swift Testing(2026 표준) + NSHostingController. (#12)
///
/// XCUITest는 러너가 다른 프로세스의 UI를 제어하므로 macOS 접근성 권한(TCC) 프롬프트가
/// 뜨고 CI에서도 불안정하다. 대신 두 축으로 검증한다:
///
/// 1. **렌더링 생존** — 뷰를 같은 프로세스에 띄워 크래시 없이 그려지는지.
///    환경 주입 누락 fatalError 등이 여기서 잡힌다 (2026-08-22 크래시 원인).
///    SwiftUI 텍스트는 NSView 하위뷰로 노출되지 않으므로 **문구 자체는 검사하지 않는다**.
/// 2. **문구 분기 로직** — 상태별 문구 결정은 DownloadTask.metaPhase(모델)에 있고
///    아래 MetaPhaseTests가 파라미터라이즈로 검증한다.
///
/// 규칙: `@Environment(QueueStore.self)`를 읽는 뷰는 반드시 `.environment()`로 주입한다.
@Suite("호스팅 뷰 렌더링 생존")
@MainActor
struct HostedViewTests {

    private func render<V: View>(_ view: V) {
        let controller = NSHostingController(rootView: view.frame(width: 900, height: 600))
        controller.view.frame = NSRect(origin: .zero, size: CGSize(width: 900, height: 600))
        controller.view.layoutSubtreeIfNeeded()
        // 여기까지 도달 = 크래시 없이 렌더링됨 (환경 누락·옵저버션 오류는 fatalError로 죽음)
    }

    private func makeStore() -> QueueStore {
        QueueStore(settings: AppSettings())
    }

    private func makeTask(state: DownloadState, progress: Double = 0,
                          speed: String = "", eta: String = "") -> DownloadTask {
        let task = DownloadTask(url: "https://youtu.be/abc", title: "테스트 영상",
                                options: DownloadOptions())
        task.state = state
        task.progress = progress
        task.speedText = speed
        task.etaText = eta
        return task
    }

    // MARK: - DownloadCardView: 전 상태에서 크래시 없이 렌더링

    @Test("다운로드 카드가 모든 상태에서 크래시 없이 렌더링된다",
          arguments: [
            DownloadState.queued, .downloading, .encoding,
            .completed, .failed, .paused, .cancelled,
          ])
    func downloadRowRendersInAllStates(_ state: DownloadState) {
        let store = makeStore()
        let task = makeTask(state: state, progress: 0.5, speed: "1 MB/s", eta: "01:00")
        render(DownloadCardView(task: task).environment(store))
    }

    @Test("추출 단계(0%·속도 없음)에서도 렌더링된다")
    func downloadRowRendersExtractingPhase() {
        let store = makeStore()
        let task = makeTask(state: .downloading, progress: 0, speed: "")
        render(DownloadCardView(task: task).environment(store))
    }

    @Test("메인 윈도우가 빈 큐로 렌더링된다")
    func mainWindowRendersEmpty() {
        let settings = AppSettings()
        let store = QueueStore(settings: settings)
        render(
            MainWindowView()
                .environment(store)
                .environment(settings)
        )
    }
}

/// 문구 분기 로직 — 뷰가 아니라 모델(DownloadTask.metaPhase)을 검증. (#11 #12)
/// 파라미터라이즈 테스트: 각 케이스가 별도 결과로 보고된다.
@Suite("메타 단계 분기")
@MainActor
struct MetaPhaseTests {

    private func makeTask(state: DownloadState, progress: Double = 0,
                          speed: String = "", eta: String = "") -> DownloadTask {
        let task = DownloadTask(url: "https://youtu.be/abc", title: "t", options: DownloadOptions())
        task.state = state
        task.progress = progress
        task.speedText = speed
        task.etaText = eta
        return task
    }

    @Test("다운로딩 + 진행률 0 + 속도 없음 = 추출 단계 (#11)")
    func extractingPhase() {
        let task = makeTask(state: .downloading, progress: 0, speed: "")
        #expect(task.metaPhase == .extracting)
    }

    @Test("다운로딩 + 속도 있음 = 다운로드 단계")
    func downloadingPhase() {
        let task = makeTask(state: .downloading, progress: 0.42, speed: "5 MB/s", eta: "01:23")
        task.downloadedBytes = 4_430_233
        task.totalBytes = 10_421_706
        guard case .downloading(let size, let speed, let eta) = task.metaPhase else {
            Issue.record("downloading이어야 함: \(task.metaPhase)")
            return
        }
        #expect(!size.isEmpty, "크기 텍스트가 있어야 함")
        #expect(speed == "5 MB/s")
        #expect(eta == "01:23")
    }

    @Test("대기 상태 = waiting (재시도 없음 → nil)")
    func waitingPhase() {
        let task = makeTask(state: .queued)
        #expect(task.metaPhase == .waiting(retry: nil))
    }

    @Test("대기 + 재시도 카운트 = waiting(retry: \"재시도 1/3\")")
    func waitingPhaseWithRetry() {
        let task = makeTask(state: .queued)
        task.retryCount = 1
        #expect(task.metaPhase == .waiting(retry: "재시도 1/3"))
    }

    @Test("일시정지 = 퍼센트 포함")
    func pausedPhase() {
        let task = makeTask(state: .paused, progress: 0.63)
        #expect(task.metaPhase == .paused(percent: 63))
    }

    @Test("인코딩/완료/실패/취소 단계")
    func terminalPhases() {
        #expect(makeTask(state: .encoding).metaPhase == .encoding)
        #expect(makeTask(state: .failed).metaPhase == .failed)
        #expect(makeTask(state: .cancelled).metaPhase == .failed)
        #expect(makeTask(state: .completed).metaPhase == .completed(subtitle: ""))
    }
}
