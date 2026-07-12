import Foundation

/// UI 컨트롤 → yt-dlp 인자 매핑의 입력값. (기획서 "파라미터 사양" 표와 1:1 대응)
struct DownloadOptions: Codable, Sendable, Equatable {
    var preset: Preset = .bestMP4

    // 부가 트랙
    var embedSubtitles: Bool = false
    var subtitleLangs: [String] = ["ko", "en"]
    var autoSubtitles: Bool = false
    var embedChapters: Bool = true
    var embedMetadata: Bool = true
    var embedThumbnail: Bool = false

    // 파워 옵션
    var sponsorBlock: Bool = false
    var cookiesFromBrowser: String? = nil   // "safari" | "chrome" | "firefox" | nil

    // 엔진
    var concurrentFragments: Int = 4
    var limitRate: String? = nil             // 예: "8M"

    // 출력 (경로는 QueueStore가 주입)
    var outputDirectory: URL = URL.moviesReel
    var outputTemplate: String = "%(title)s.%(ext)s"   // 영상 제목 그대로 (ID 포함은 설정에서)

    // 플레이리스트
    var playlistMode: PlaylistMode = .single  // 단일 영상이 기본값 — 실수로 전체를 받는 일 방지
    var maxPlaylistItems: Int = 50            // .all 일 때 한 번에 받을 수 있는 상한

    /// 기본 생성자 (모든 프로퍼티에 기본값) — 커스텀 Codable init 때문에 멤버와이즈 생성자가 사라져서 명시 제공.
    init() {}

    // MARK: - Codable (구버전 JSON 호환 — 새 필드가 없으면 기본값 사용)

    enum CodingKeys: String, CodingKey {
        case preset, embedSubtitles, subtitleLangs, autoSubtitles, embedChapters
        case embedMetadata, embedThumbnail, sponsorBlock, cookiesFromBrowser
        case concurrentFragments, limitRate, outputDirectory, outputTemplate
        case playlistMode, maxPlaylistItems
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        preset = try c.decodeIfPresent(Preset.self, forKey: .preset) ?? .bestMP4
        embedSubtitles = try c.decodeIfPresent(Bool.self, forKey: .embedSubtitles) ?? false
        subtitleLangs = try c.decodeIfPresent([String].self, forKey: .subtitleLangs) ?? ["ko", "en"]
        autoSubtitles = try c.decodeIfPresent(Bool.self, forKey: .autoSubtitles) ?? false
        embedChapters = try c.decodeIfPresent(Bool.self, forKey: .embedChapters) ?? true
        embedMetadata = try c.decodeIfPresent(Bool.self, forKey: .embedMetadata) ?? true
        embedThumbnail = try c.decodeIfPresent(Bool.self, forKey: .embedThumbnail) ?? false
        sponsorBlock = try c.decodeIfPresent(Bool.self, forKey: .sponsorBlock) ?? false
        cookiesFromBrowser = try c.decodeIfPresent(String.self, forKey: .cookiesFromBrowser)
        concurrentFragments = try c.decodeIfPresent(Int.self, forKey: .concurrentFragments) ?? 4
        limitRate = try c.decodeIfPresent(String.self, forKey: .limitRate)
        outputDirectory = try c.decodeIfPresent(URL.self, forKey: .outputDirectory) ?? URL.moviesReel
        outputTemplate = try c.decodeIfPresent(String.self, forKey: .outputTemplate) ?? "%(title)s.%(ext)s"
        playlistMode = try c.decodeIfPresent(PlaylistMode.self, forKey: .playlistMode) ?? .single
        maxPlaylistItems = try c.decodeIfPresent(Int.self, forKey: .maxPlaylistItems) ?? 50
    }
}

/// 플레이리스트 처리 정책.
/// - single: 해당 링크의 영상 1개만 (`--no-playlist`)
/// - all: 전체 플레이리스트 확장해서 항목별로 큐에 추가
enum PlaylistMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case single
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .single: "이 영상만"
        case .all: "전체 플레이리스트"
        }
    }

    var shortTitle: String {
        switch self {
        case .single: "단일"
        case .all: "전체"
        }
    }

    var symbol: String {
        switch self {
        case .single: "play.rectangle"
        case .all: "rectangle.stack"
        }
    }
}

extension URL {
    /// 기본 저장 폴더 ~/Movies/Reel — 없으면 생성 시도.
    static var moviesReel: URL {
        let base = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Movies")
        let dir = base.appending(path: "Reel", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}