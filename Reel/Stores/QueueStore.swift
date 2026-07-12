import AppKit
import Observation
import UserNotifications

/// 사이드바 필터.
enum QueueFilter: String, CaseIterable, Identifiable {
    case inProgress, queued, completed, failed, all, audio, stats
    var id: String { rawValue }

    var title: String {
        switch self {
        case .inProgress: "진행 중"
        case .queued: "대기"
        case .completed: "완료"
        case .failed: "실패"
        case .all: "전체 항목"
        case .audio: "오디오"
        case .stats: "통계"
        }
    }
    var symbol: String {
        switch self {
        case .inProgress: "arrow.down.circle"
        case .queued: "clock"
        case .completed: "checkmark.circle"
        case .failed: "exclamationmark.triangle"
        case .all: "square.grid.2x2"
        case .audio: "music.note"
        case .stats: "chart.bar.xaxis"
        }
    }
    @MainActor
    func matches(_ task: DownloadTask) -> Bool {
        switch self {
        case .inProgress: task.state.isActive || task.state == .paused
        case .queued: task.state == .queued
        case .completed: task.state == .completed
        case .failed: task.state == .failed || task.state == .cancelled
        case .all: true
        case .audio: task.options.preset.isAudioOnly
        case .stats: false   // 통계는 항목 매칭 없음 — 별도 화면
        }
    }
}

/// 큐의 단일 진실 공급원. 동시성 스케줄링 + 영속화 + 엔진 이벤트 소비를 담당.
@MainActor
@Observable
final class QueueStore {
    var tasks: [DownloadTask] = []

    let settings: AppSettings
    private let engine = DownloadEngine()
    @ObservationIgnored private var consumers: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var retryTimers: [UUID: Task<Void, Never>] = [:]

    init(settings: AppSettings) {
        self.settings = settings
        load()
        autoClearOldCompleted()
        requestNotificationAuth()
        pump()   // 복원된 대기 항목 이어받기
    }

    // MARK: - 공개 API

    /// 같은 URL이 이미 대기/진행 중인가 — 중복 추가 방지 및 배너 분기용.
    func activeDuplicate(of url: String) -> DownloadTask? {
        tasks.first { $0.url == url && ($0.state.isActive || $0.state == .queued || $0.state == .paused) }
    }

    @discardableResult
    func add(url: String, preset: Preset? = nil, playlistMode: PlaylistMode? = nil) -> DownloadTask {
        // 대기/진행 중인 동일 URL은 새로 만들지 않는다. (완료·실패는 재다운로드 허용)
        if let existing = activeDuplicate(of: url) { return existing }
        let mode = playlistMode ?? settings.defaultPlaylistMode
        let options = settings.makeOptions(preset: preset ?? settings.defaultPreset, playlistMode: mode)
        let task = DownloadTask(url: url, title: url, options: options)
        tasks.insert(task, at: 0)
        save()
        prefetchMetadata(for: task)

        // 플레이리스트 전체 모드면 항목별로 확장 — 메타데이터 후 처리.
        // 확장 중에는 pump()가 자리 표시 항목을 시작하지 않도록 막는다.
        if mode == .all {
            task.isExpanding = true
            expandPlaylist(for: task)
        }
        pump()
        return task
    }

    /// 여러 URL을 한 번에 큐에 추가. 추가된 항목 수 반환.
    @discardableResult
    func addMany(urls: [String], preset: Preset? = nil, playlistMode: PlaylistMode? = nil) -> Int {
        var n = 0
        for url in urls {
            add(url: url, preset: preset, playlistMode: playlistMode)
            n += 1
        }
        return n
    }

    /// 클립보드/입력 문자열에서 URL들을 꺼내 큐에 추가. 추가된 항목 수 반환.
    @discardableResult
    func addManyFromText(_ text: String, preset: Preset? = nil, playlistMode: PlaylistMode? = nil) -> Int {
        let urls = ClipboardMonitor.extractMediaURLs(from: text)
        guard !urls.isEmpty else { return 0 }
        return addMany(urls: urls, preset: preset, playlistMode: playlistMode)
    }

    func cancel(_ task: DownloadTask) {
        // 재시도 보류 중이면 타이머만 취소하고 종료 상태로.
        retryTimers[task.id]?.cancel()
        retryTimers[task.id] = nil

        if task.state == .queued {
            task.state = .cancelled
            task.retryAfter = nil
            save()
            return
        }
        let id = task.id
        Task { await engine.cancel(id: id) }
    }

    func pause(_ task: DownloadTask) {
        guard task.state == .downloading else { return }
        let id = task.id
        Task { await engine.pause(id: id) }
        task.state = .paused
        task.speedText = ""; task.etaText = ""
    }

    func resume(_ task: DownloadTask) {
        guard task.state == .paused else { return }
        let id = task.id
        Task { await engine.resume(id: id) }
        task.state = .downloading
    }

    func retry(_ task: DownloadTask) {
        guard task.state.isRestartable else { return }
        task.state = .queued
        task.progress = 0
        task.errorMessage = nil
        task.retryCount = 0
        task.retryAfter = nil
        save()
        pump()
    }

    func remove(_ task: DownloadTask) {
        let id = task.id
        if task.state.isActive || task.state == .paused {
            Task { await engine.cancel(id: id) }
        }
        retryTimers[id]?.cancel()
        retryTimers[id] = nil
        consumers[id]?.cancel()
        consumers[id] = nil
        tasks.removeAll { $0.id == id }
        save()
    }

    func clearCompleted() {
        tasks.removeAll { $0.state == .completed }
        save()
    }

    /// 지원 사이트 목록(설정 탭에서 사용). 캐시는 뷰가 보관.
    func supportedSites() async -> [String] {
        await engine.listExtractors()
    }

    /// yt-dlp 버전 문자열.
    func ytdlpVersion() async -> String? {
        await engine.ytdlpVersion()
    }

    /// yt-dlp 자체 업데이트 시도. (성공 여부, 메시지)
    func updateYtdlp() async -> (ok: Bool, message: String) {
        await engine.updateYtdlp()
    }

    /// 클립보드에서 URL을 꺼내 바로 큐에 추가. 성공 시 추가된 항목 반환.
    @discardableResult
    func addFromPasteboard() -> DownloadTask? {
        guard let raw = NSPasteboard.general.string(forType: .string),
              let url = ClipboardMonitor.extractMediaURL(from: raw) else { return nil }
        return add(url: url)
    }

    func revealInFinder(_ task: DownloadTask) {
        guard let path = task.outputPath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func openFile(_ task: DownloadTask) {
        guard let path = task.outputPath else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    // MARK: - 파생

    func filtered(_ filter: QueueFilter) -> [DownloadTask] {
        tasks.filter { filter.matches($0) }
    }
    func count(_ filter: QueueFilter) -> Int {
        tasks.reduce(0) { $0 + (filter.matches($1) ? 1 : 0) }
    }
    var activeCount: Int { tasks.reduce(0) { $0 + ($1.state.isActive ? 1 : 0) } }
    var queuedCount: Int { tasks.reduce(0) { $0 + ($1.state == .queued ? 1 : 0) } }
    var completedToday: Int {
        tasks.reduce(0) { $0 + ($1.state == .completed && Calendar.current.isDateInToday($1.createdAt) ? 1 : 0) }
    }
    var recent: [DownloadTask] { Array(tasks.prefix(6)) }

    /// 메뉴바/상태바용 전체 진행률 — 활성 항목들의 평균 (인코딩은 0.95로 간주).
    var overallProgress: Double {
        let active = tasks.filter { $0.state.isActive }
        guard !active.isEmpty else { return 0 }
        let sum = active.reduce(0.0) { $0 + ($1.state == .encoding ? 0.95 : $1.progress) }
        return sum / Double(active.count)
    }

    // MARK: - 통계

    /// 다운로드 통계 요약. 완료 항목 기준.
    var stats: DownloadStats {
        let completed = tasks.filter { $0.state == .completed }
        let totalBytes = completed.reduce(Int64(0)) { $0 + ($1.totalBytes ?? Int64($1.downloadedBytes)) }
        let thisMonth = completed.filter { Calendar.current.isDate($0.completedAt ?? $0.createdAt, equalTo: Date(), toGranularity: .month) }.count
        let byHost: [String: Int] = completed.reduce(into: [:]) { acc, t in
            guard let h = t.host else { return }
            acc[h, default: 0] += 1
        }
        let byPreset: [Preset: Int] = completed.reduce(into: [:]) { acc, t in
            acc[t.options.preset, default: 0] += 1
        }
        return DownloadStats(
            completedCount: completed.count,
            thisMonthCount: thisMonth,
            totalBytes: totalBytes,
            byHost: byHost,
            byPreset: byPreset
        )
    }

    // MARK: - 스케줄러

    private func pump() {
        var slots = settings.effectiveConcurrency - activeCount
        guard slots > 0 else { return }
        let now = Date()
        for task in tasks.reversed() where task.state == .queued && slots > 0 {
            // 플레이리스트 확장 중인 자리 표시 항목은 아직 시작하지 않는다.
            if task.isExpanding { continue }
            // 재시도 보류 중이면 아직 시작하지 않는다.
            if let after = task.retryAfter, after > now { continue }
            task.retryAfter = nil
            start(task)
            slots -= 1
        }
    }

    private func start(_ task: DownloadTask) {
        task.state = .downloading
        task.errorMessage = nil
        let id = task.id, url = task.url, options = task.options
        let consumer = Task { @MainActor [weak self] in
            guard let self else { return }
            let stream = await self.engine.events(id: id, url: url, options: options)
            for await event in stream {
                self.handle(event, for: task)
            }
            self.consumers[id] = nil
            self.pump()
            self.save()
        }
        consumers[id] = consumer
    }

    private func handle(_ event: EngineEvent, for task: DownloadTask) {
        switch event {
        case .started:
            if task.state == .queued { task.state = .downloading }
        case .phase(let s):
            task.state = s
        case .progress(let fraction, let speed, let eta, let downloaded, let total):
            if task.state != .encoding { task.state = .downloading }
            task.progress = fraction
            task.speedText = speed
            task.etaText = eta
            task.downloadedBytes = downloaded
            if let total { task.totalBytes = total }
        case .destination(let path), .finalFile(let path):
            task.outputPath = path
        case .completed:
            task.state = .completed
            task.progress = 1
            task.speedText = ""; task.etaText = ""
            task.completedAt = Date()
            notifyComplete(task)
        case .cancelled:
            if task.state != .completed { task.state = .cancelled }
            task.retryAfter = nil
            task.speedText = ""; task.etaText = ""
        case .failed(let message):
            handleFailure(message, for: task)
        }
    }

    /// 실패 처리 — 일시적 오류면 지수 백오프로 자동 재시도, 아니면 실패 종료.
    private func handleFailure(_ message: String, for task: DownloadTask) {
        let canRetry = task.retryCount < DownloadTask.maxRetries && Self.isRetryableError(message)
        guard canRetry else {
            task.state = .failed
            task.errorMessage = message
            task.speedText = ""; task.etaText = ""
            return
        }
        // 자동 재시도 예약
        task.retryCount += 1
        task.state = .queued
        task.errorMessage = message   // 행에서 요지 표시용으로 유지
        task.speedText = ""; task.etaText = ""
        let delay = pow(2.0, Double(task.retryCount))   // 2s, 4s, 8s
        task.retryAfter = Date().addingTimeInterval(delay)
        save()
        scheduleRetryPump(after: delay, for: task.id)
    }

    /// 보류 시각이 지난 뒤 pump()를 한 번 더 돌려 재시도를 시작.
    private func scheduleRetryPump(after delay: Double, for id: UUID) {
        retryTimers[id]?.cancel()
        let nanos = UInt64(max(0.1, delay) * 1_000_000_000)
        let t = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: nanos)
            guard self != nil else { return }
            self?.retryTimers[id] = nil
            self?.pump()
        }
        retryTimers[id] = t
    }

    /// 일시적 오류 키워드 판별 — 자동 재시도 대상.
    static func isRetryableError(_ message: String) -> Bool {
        let m = message.lowercased()
        let keywords = ["429", "502", "503", "504", "timeout", "timed out",
                        "connection", "temporary", "rate limit", "rate-limit",
                        "network", "unreachable", "reset by peer",
                        "socket", "fragment", "retry"]
        // 명백한 영구 실패(연령 제한·지역 제한·권한)는 제외
        let permanent = ["sign in to confirm", "age-restricted", "geo restricted",
                         "private video", "members-only", "not available"]
        if permanent.contains(where: { m.contains($0) }) { return false }
        return keywords.contains(where: { m.contains($0) })
    }

    // MARK: - 메타데이터 / 플레이리스트 확장

    private func prefetchMetadata(for task: DownloadTask) {
        let url = task.url
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let meta = try? await self.engine.fetchMetadata(url: url) {
                task.apply(metadata: meta)
                self.save()
            }
        }
    }

    /// 단일 영상 메타데이터와 플레이리스트 정보를 비동기로 가져온다.
    private func expandPlaylist(for placeholder: DownloadTask) {
        let url = placeholder.url
        let preset = placeholder.options.preset
        let maxItems = placeholder.options.maxPlaylistItems
        Task { @MainActor [weak self] in
            guard let self else { return }
            // 단일 영상 메타는 먼저 채워 표시
            if let meta = try? await self.engine.fetchMetadata(url: url) {
                placeholder.apply(metadata: meta)
                self.save()
            }
            // 플레이리스트 감지 — 아니면 자리 표시 항목을 단일 다운로드로 전환
            // 사용자가 취소/제거했으면 확장을 중단한다.
            guard self.tasks.contains(where: { $0.id == placeholder.id }),
                  placeholder.state != .cancelled else { return }
            guard let info = try? await self.engine.fetchPlaylistInfo(url: url),
                  info.isPlaylist, !info.entries.isEmpty else {
                // 단일 영상: 전체 모드 플래그를 풀고 단일로 다운로드
                placeholder.isExpanding = false
                placeholder.options.playlistMode = .single
                self.save()
                self.pump()
                return
            }
            // 자리 표시 항목을 실제 항목들로 교체
            self.tasks.removeAll { $0.id == placeholder.id }
            self.consumers[placeholder.id]?.cancel()
            self.consumers[placeholder.id] = nil

            let entries = Array(info.entries.prefix(max(maxItems, 1)))
            var inserted: [DownloadTask] = []
            for (i, entry) in entries.enumerated() {
                // 항목별 단일 다운로드 옵션 — 각각 개별 진행률 추적
                var o = self.settings.makeOptions(preset: preset, playlistMode: .single)
                o.playlistMode = .single
                let title = entry.title.isEmpty ? "항목 \(i + 1)" : entry.title
                let t = DownloadTask(url: entry.url, title: title, options: o)
                self.tasks.insert(t, at: i)   // 플레이리스트 순서 유지
                inserted.append(t)
            }
            self.save()
            // 메타데이터 프리페치 + 스케줄 시작
            for t in inserted { self.prefetchMetadata(for: t) }
            self.pump()
        }
    }

    // MARK: - 알림

    private func requestNotificationAuth() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    private func notifyComplete(_ task: DownloadTask) {
        guard settings.notifyOnComplete else { return }
        let content = UNMutableNotificationContent()
        content.title = "다운로드 완료"
        content.body = task.title
        content.sound = .default
        let request = UNNotificationRequest(identifier: task.id.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - 영속화

    private var storeURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appending(path: "Reel", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appending(path: "queue.json")
    }

    func save() {
        let snapshots = tasks.map { $0.snapshot }
        if let data = try? JSONEncoder().encode(snapshots) {
            try? data.write(to: storeURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let snapshots = try? JSONDecoder().decode([DownloadTask.Snapshot].self, from: data) else { return }
        tasks = snapshots.map { DownloadTask(snapshot: $0) }
    }

    /// 시작 시 완료 항목 자동 정리 — 설정이 켜져 있으면 기준일 이상 지난 완료 항목 제거.
    private func autoClearOldCompleted() {
        guard settings.autoClearCompleted else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -settings.autoClearAfterDays, to: Date()) ?? Date()
        let before = tasks.count
        tasks.removeAll { task in
            guard task.state == .completed else { return false }
            let date = task.completedAt ?? task.createdAt
            return date < cutoff
        }
        if tasks.count != before { save() }
    }
}

/// 통계 요약 모델.
struct DownloadStats: Sendable {
    var completedCount: Int
    var thisMonthCount: Int
    var totalBytes: Int64
    var byHost: [String: Int]
    var byPreset: [Preset: Int]

    /// 상위 N개 사이트 (다운로드 수 내림차순).
    func topHosts(_ n: Int = 5) -> [(host: String, count: Int)] {
        byHost.sorted { $0.value > $1.value }.prefix(n).map { ($0.key, $0.value) }
    }
    func topPresets() -> [(preset: Preset, count: Int)] {
        byPreset.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }
}
