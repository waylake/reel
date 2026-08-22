import Foundation

/// yt-dlp --dump-single-json 에서 UI에 필요한 필드만 추린 값.
struct MediaMetadata: Sendable {
    var title: String
    var durationSeconds: Double?
    var thumbnailURL: URL?
    var width: Int?
    var height: Int?
    var vcodec: String?
    var approxBytes: Double?
    var uploader: String?

    /// 플레이리스트 항목 1개 (flat-playlist 결과의 entry).
    struct PlaylistEntry: Sendable, Identifiable {
        var url: String
        var title: String
        var durationSeconds: Double?
        var id: String { url }
    }

    /// `--flat-playlist --print` 결과 해석 — 단일 영상인지 플레이리스트/채널인지, 항목 목록.
    /// 줄 형태: `SENTINEL|id|url|duration|uploader|title` (제목은 파이프를 가질 수 있어 마지막).
    struct PlaylistInfo: Sendable {
        var isPlaylist: Bool
        var count: Int?              // 항목 수
        var entries: [PlaylistEntry]
        var channelName: String?      // 채널/업로더 표시명 (없을 수 있음)
    }

    // MARK: - 단일 영상 메타데이터 (--no-playlist)

    private struct DTO: Decodable {
        let title: String?
        let duration: Double?
        let thumbnail: String?
        let width: Int?
        let height: Int?
        let vcodec: String?
        let filesize_approx: Double?
        let uploader: String?
    }

    init?(jsonData: Data) {
        if let dto = try? JSONDecoder().decode(DTO.self, from: jsonData) {
            self.init(dto: dto)
            return
        }
        // 여러 줄로 나올 경우 첫 JSON 객체만 시도
        if let first = String(data: jsonData, encoding: .utf8)?
            .split(whereSeparator: \.isNewline)
            .first(where: { $0.hasPrefix("{") }),
           let d = String(first).data(using: .utf8),
           let dto = try? JSONDecoder().decode(DTO.self, from: d) {
            self.init(dto: dto)
            return
        }
        return nil
    }

    private init(dto: DTO) {
        title = dto.title ?? "제목 없음"
        durationSeconds = dto.duration
        thumbnailURL = dto.thumbnail.flatMap { URL(string: $0) }
        width = dto.width
        height = dto.height
        vcodec = (dto.vcodec == "none") ? nil : dto.vcodec
        approxBytes = dto.filesize_approx
        uploader = dto.uploader
    }

    // MARK: - 플레이리스트 정보 (--flat-playlist --print)

    /// `--flat-playlist --print` 줄 출력에서 항목 목록과 채널명을 뽑는다.
    /// 큰 채널(수백 항목)에서 `--dump-single-json`이 JSON을 잘려 개수가 틀렸던 문제를
    /// 줄 기반 파싱으로 해결한다. 항목이 2개 이상이면 플레이리스트/채널로 본다.
    static func playlistInfo(from data: Data) -> PlaylistInfo? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let s = ArgumentBuilder.sentinel

        var entries: [PlaylistEntry] = []
        var channelName: String? = nil

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            guard line.hasPrefix(s) else { continue }
            // s | id | url | duration | uploader | title...
            let parts = line.components(separatedBy: "|")
            guard parts.count >= 6, parts[0] == s else { continue }

            let url = parts[2]
            guard !url.isEmpty else { continue }

            let duration = (parts[3] == "NA" || parts[3].isEmpty) ? nil : Double(parts[3])

            if channelName == nil, parts[4] != "NA", !parts[4].isEmpty { channelName = parts[4] }

            let title = parts[5...].joined(separator: "|")
            entries.append(PlaylistEntry(url: url, title: title.isEmpty ? url : title, durationSeconds: duration))
        }

        // 항목 2개 이상이면 플레이리스트/채널 (단일 영상은 flat-playlist로 1줄만 출력).
        let isPlaylist = entries.count >= 2
        return PlaylistInfo(isPlaylist: isPlaylist, count: entries.count, entries: entries, channelName: channelName)
    }
}
