import Foundation
import Observation

/// 큐의 한 항목(런타임). 진행률은 초당 여러 번 갱신되므로 @Model이 아닌 @Observable + 스냅샷 영속화 사용.
@MainActor
@Observable
final class DownloadTask: Identifiable {
    let id: UUID
    let url: String
    let createdAt: Date

    var title: String
    var thumbnailURL: URL?
    var durationSeconds: Double?
    var options: DownloadOptions

    var state: DownloadState = .queued
    var progress: Double = 0            // 0...1
    var speedText: String = ""
    var etaText: String = ""
    var downloadedBytes: Int64 = 0
    var totalBytes: Int64?
    var outputPath: String?
    var errorMessage: String?

    /// 자동 재시도 횟수 (0 = 아직 시도 안 함). 최대 maxRetries까지.
    var retryCount: Int = 0
    /// 일시적 실패 후 재시도를 보류하는 시각. pump()는 이 시각이 지나야 시작한다.
    var retryAfter: Date?
    /// 완료 시각 — 자동 정리 기준.
    var completedAt: Date?

    /// 플레이리스트 전체 모드에서 항목 확장이 진행 중인 자리 표시 항목 표시.
    /// pump()가 확장 중인 항목을 시작하지 않도록 막는다. (런타임 전용, 영속화 안 함)
    var isExpanding: Bool = false

    /// 자동 재시도 상한.
    static let maxRetries = 3

    init(id: UUID = UUID(),
         url: String,
         title: String,
         options: DownloadOptions,
         createdAt: Date = Date()) {
        self.id = id
        self.url = url
        self.title = title
        self.options = options
        self.createdAt = createdAt
    }

    /// 미리보기 메타데이터 반영.
    func apply(metadata: MediaMetadata) {
        if title.isEmpty || title == url { title = metadata.title }
        else if !metadata.title.isEmpty { title = metadata.title }
        thumbnailURL = metadata.thumbnailURL
        durationSeconds = metadata.durationSeconds
        if totalBytes == nil, let approx = metadata.approxBytes { totalBytes = Int64(approx) }
        metaSubtitle = [
            Fmt.duration(metadata.durationSeconds),
            Fmt.resolutionLabel(width: metadata.width, height: metadata.height, vcodec: metadata.vcodec),
            Fmt.bytes(metadata.approxBytes)
        ].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// 목록 부제(길이 · 해상도 · 용량).
    var metaSubtitle: String = ""

    /// 진행 용량 텍스트 "142 / 240 MB".
    var sizeText: String {
        let d = Fmt.bytes(downloadedBytes)
        if let totalBytes, totalBytes > 0 {
            return "\(d) / \(Fmt.bytes(totalBytes))"
        }
        return d
    }

    /// 재시도 표기 — "재시도 1/3". 대기 중일 때만 의미.
    var retryText: String? {
        guard retryCount > 0 else { return nil }
        return "재시도 \(retryCount)/\(Self.maxRetries)"
    }

    /// 다운로드 호스트(사이트) — 통계용.
    var host: String? { URL(string: url)?.host?.lowercased() }

    // MARK: - 영속화 스냅샷

    struct Snapshot: Codable {
        var id: UUID
        var url: String
        var title: String
        var createdAt: Date
        var options: DownloadOptions
        var stateRaw: String
        var progress: Double
        var outputPath: String?
        var durationSeconds: Double?
        var thumbnail: String?
        var metaSubtitle: String
        var retryCount: Int?
        var completedAt: Date?
    }

    var snapshot: Snapshot {
        // 앱 재시작 시 진행 중이던 항목은 대기로 되돌린다. 재시도 보류도 초기화.
        let restored: DownloadState = state.isActive ? .queued : state
        return Snapshot(id: id, url: url, title: title, createdAt: createdAt,
                        options: options, stateRaw: restored.rawValue, progress: progress,
                        outputPath: outputPath, durationSeconds: durationSeconds,
                        thumbnail: thumbnailURL?.absoluteString, metaSubtitle: metaSubtitle,
                        retryCount: retryCount, completedAt: completedAt)
    }

    convenience init(snapshot s: Snapshot) {
        self.init(id: s.id, url: s.url, title: s.title, options: s.options, createdAt: s.createdAt)
        state = DownloadState(rawValue: s.stateRaw) ?? .queued
        progress = s.progress
        outputPath = s.outputPath
        durationSeconds = s.durationSeconds
        thumbnailURL = s.thumbnail.flatMap { URL(string: $0) }
        metaSubtitle = s.metaSubtitle
        retryCount = s.retryCount ?? 0
        completedAt = s.completedAt
    }
}
