import AppKit
import Observation
import UserNotifications

/// 사이드바 필터.
enum QueueFilter: String, CaseIterable, Identifiable {
    case inProgress, queued, completed, failed, all, audio
    var id: String { rawValue }

    var title: String {
        switch self {
        case .inProgress: "진행 중"
        case .queued: "대기"
        case .completed: "완료"
        case .failed: "실패"
        case .all: "전체 항목"
        case .audio: "오디오"
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

    init(settings: AppSettings) {
        self.settings = settings
        load()
        requestNotificationAuth()
        pump()   // 복원된 대기 항목 이어받기
    }

    // MARK: - 공개 API

    /// 같은 URL이 이미 대기/진행 중인가 — 중복 추가 방지 및 배너 분기용.
    func activeDuplicate(of url: String) -> DownloadTask? {
        tasks.first { $0.url == url && ($0.state.isActive || $0.state == .queued || $0.state == .paused) }
    }

    @discardableResult
    func add(url: String, preset: Preset? = nil) -> DownloadTask {
        // 대기/진행 중인 동일 URL은 새로 만들지 않는다. (완료·실패는 재다운로드 허용)
        if let existing = activeDuplicate(of: url) { return existing }
        let options = settings.makeOptions(preset: preset ?? settings.defaultPreset)
        let task = DownloadTask(url: url, title: url, options: options)
        tasks.insert(task, at: 0)
        save()
        prefetchMetadata(for: task)
        pump()
        return task
    }

    func cancel(_ task: DownloadTask) {
        if task.state == .queued {
            task.state = .cancelled
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
        save()
        pump()
    }

    func remove(_ task: DownloadTask) {
        let id = task.id
        if task.state.isActive || task.state == .paused {
            Task { await engine.cancel(id: id) }
        }
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

    // MARK: - 스케줄러

    private func pump() {
        var slots = settings.effectiveConcurrency - activeCount
        guard slots > 0 else { return }
        for task in tasks.reversed() where task.state == .queued && slots > 0 {
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
            notifyComplete(task)
        case .cancelled:
            if task.state != .completed { task.state = .cancelled }
            task.speedText = ""; task.etaText = ""
        case .failed(let message):
            task.state = .failed
            task.errorMessage = message
            task.speedText = ""; task.etaText = ""
        }
    }

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
}
