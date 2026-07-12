import Foundation

/// UI 옵션 → yt-dlp 인자 배열 조립. 기획서 "파라미터 사양" 표의 구현체(계약).
enum ArgumentBuilder {
    /// stdout에서 우리 데이터 라인을 식별하기 위한 접두어.
    static let sentinel = "@@RP@@"

    /// 단일 영상 메타데이터용 인자 (--no-playlist).
    /// --ignore-config: 사용자 전역 설정(~/.config/yt-dlp/config)의 영향을 배제해 결정론 보장.
    static func metadataArgs(url: String) -> [String] {
        ["--ignore-config", "--dump-single-json", "--no-playlist", "--no-warnings", "--no-progress", url]
    }

    /// 플레이리스트 감지용 인자 (--flat-playlist).
    /// 단일 영상 URL이면 1개짜리 결과, 플레이리스트면 entries 배열을 준다.
    static func playlistArgs(url: String) -> [String] {
        ["--ignore-config", "--flat-playlist", "--dump-single-json", "--no-warnings", "--no-progress", url]
    }

    /// 실제 다운로드 인자.
    static func downloadArgs(url: String, options: DownloadOptions) -> [String] {
        // --ignore-config: 사용자 전역 설정 배제(예: --download-archive가 재다운로드를 막는 문제).
        // --progress: stderr가 tty가 아닐 때(Process 파이프) 진행률을 강제 출력.
        // --continue: .part 파일이 있으면 이어받기 (yt-dlp 기본값이지만 명시해 의도를 고정).
        var a: [String] = ["--ignore-config", "--newline", "--progress", "--no-warnings",
                           "--no-color", "--continue"]

        // 구조화 진행률 — stdout 스크래핑 대신 progress-template로 안정 파싱
        a += ["--progress-template",
              "download:\(sentinel)%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s|%(progress.downloaded_bytes)s|%(progress.total_bytes)s"]

        // 헬퍼 위치
        if let loc = BinaryResolver.ffmpegLocation { a += ["--ffmpeg-location", loc] }

        // 엔진 튜닝
        a += ["-N", String(max(1, options.concurrentFragments))]
        if let rate = options.limitRate, !rate.isEmpty { a += ["--limit-rate", rate] }

        // 플레이리스트 정책 — 단일이면 이 영상만, 전체면 플레이리스트 모두.
        // (all 모드는 QueueStore가 항목별로 확장해서 내려오므로 여기서는 사실상 single만 쓰지만,
        //  직접 다운로드 경로도 안전하게 처리한다.)
        switch options.playlistMode {
        case .single:
            a += ["--no-playlist"]
        case .all:
            a += ["--yes-playlist"]
            if options.maxPlaylistItems > 0 {
                a += ["--playlist-items", "1-\(options.maxPlaylistItems)"]
            }
        }

        // 포맷 프리셋
        switch options.preset {
        case .bestMP4:
            a += ["-f", "bv*+ba/b", "--merge-output-format", "mp4"]
        case .hd1080:
            a += ["-f", "bv*[height<=1080]+ba/b[height<=1080]", "--merge-output-format", "mp4"]
        case .audioMP3:
            a += ["-x", "--audio-format", "mp3", "--audio-quality", "0"]
        case .audioM4A:
            a += ["-f", "ba/b", "-x", "--audio-format", "m4a"]
        case .original:
            break
        }

        // 부가 트랙
        if options.embedSubtitles && !options.preset.isAudioOnly {
            a += ["--write-subs"]
            if options.autoSubtitles { a += ["--write-auto-subs"] }
            a += ["--sub-langs", options.subtitleLangs.joined(separator: ",")]
            a += ["--embed-subs"]
        }
        if options.embedChapters { a += ["--embed-chapters"] }
        if options.embedMetadata { a += ["--embed-metadata"] }
        if options.embedThumbnail { a += ["--embed-thumbnail"] }
        if options.sponsorBlock { a += ["--sponsorblock-remove", "sponsor,selfpromo,interaction"] }
        if let browser = options.cookiesFromBrowser, !browser.isEmpty {
            a += ["--cookies-from-browser", browser]
        }

        // 출력
        a += ["-o", options.outputTemplate, "-P", options.outputDirectory.path]

        // 최종 파일 경로 출력 (이동 완료 후). --print는 기본 simulate이므로 --no-simulate 필요.
        a += ["--print", "after_move:\(sentinel)FILE|%(filepath)s", "--no-simulate"]

        a.append(url)
        return a
    }

    /// 화면 C(포맷 인스펙터) 하단 "실제 실행될 명령" 미리보기용 문자열.
    static func previewCommand(url: String, options: DownloadOptions) -> String {
        let args = downloadArgs(url: url, options: options)
            .map { $0.contains(" ") ? "\"\($0)\"" : $0 }
            .joined(separator: " ")
        return "yt-dlp \(args)"
    }
}
