import Foundation

/// yt-dlp / ffmpeg 실행 파일 위치 결정.
/// 0순위: 앱 자체 관리본 (Application Support — 설정의 "yt-dlp 업데이트"가 설치)
/// 1순위: 앱 번들 Resources (배포용 스탠드얼론 바이너리)
/// 2순위: 개발 머신 표준 경로 (Homebrew / MacPorts)
enum BinaryResolver {
    /// 앱이 직접 내려받아 관리하는 바이너리 디렉터리.
    /// 번들본은 읽기 전용이라 yt-dlp가 낡으면 앱 릴리즈 전까지 고칠 방법이 없는데,
    /// 유튜브 추출기는 그보다 훨씬 자주 망가지므로 런타임 업데이트 경로를 둔다.
    static let managedDir: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        .appending(path: "Reel/bin", directoryHint: .isDirectory)

    static func url(for name: String) -> URL? {
        // 0) 자체 관리본 — 설정에서 업데이트한 최신 yt-dlp. 항상 번들본보다 우선한다.
        let managed = managedDir.appending(path: name)
        if FileManager.default.isExecutableFile(atPath: managed.path) {
            return managed
        }
        // 1) 번들 동봉본 — bundle-binaries.sh가 빌드 후 Resources/에 복사
        //    Bundle.main.url(forResource:)는 빌드 시 리소스 맵을 사용하므로
        //    런타임 추가 파일은 직접 경로로 접근해야 함.
        let bundled = Bundle.main.bundleURL.appending(path: "Resources/").appending(path: name)
        if FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }
        // 2) 개발 머신 표준 경로
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/opt/local/bin/\(name)",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    static var ytdlp: URL? { url(for: "yt-dlp") }
    static var ffmpeg: URL? { url(for: "ffmpeg") }

    /// ffmpeg가 있는 디렉터리 — yt-dlp에 --ffmpeg-location으로 전달.
    static var ffmpegLocation: String? { ffmpeg?.deletingLastPathComponent().path }

    /// yt-dlp가 앱 번들에 포함된 바이너리인지 (배포 빌드).
    /// 번들본은 쓰기 불가능해 `-U` 자체 업데이트가 안 되므로
    /// 업데이트 시 GitHub 릴리스를 Application Support로 내려받는다.
    static var isBundled: Bool {
        guard let y = ytdlp else { return false }
        let resources = Bundle.main.bundleURL.appending(path: "Resources/").path
        return y.path.hasPrefix(resources)
    }
}

enum EngineError: LocalizedError {
    case ytdlpNotFound
    case metadataFailed(String)
    case processFailed(code: Int32, message: String)
    case updateFailed(String)

    var errorDescription: String? {
        switch self {
        case .ytdlpNotFound:
            "yt-dlp를 찾을 수 없습니다. Homebrew로 설치하거나(brew install yt-dlp) 앱에 번들해 주세요."
        case .metadataFailed(let m):
            "영상 정보를 가져오지 못했습니다: \(m)"
        case .processFailed(let code, let m):
            "다운로드 실패 (코드 \(code)): \(m)"
        case .updateFailed(let m):
            "yt-dlp 업데이트 실패: \(m)"
        }
    }
}
