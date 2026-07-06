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
