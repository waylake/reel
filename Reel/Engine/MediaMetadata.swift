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

    /// `--flat-playlist` 결과 해석 — 단일 영상인지 플레이리스트인지, 항목 목록.
    struct PlaylistInfo: Sendable {
        var isPlaylist: Bool
        var count: Int?              // playlist_count (없을 수 있음)
        var entries: [PlaylistEntry]
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

    // MARK: - 플레이리스트 정보 (--flat-playlist)

    /// `--flat-playlist --dump-single-json` 결과에서 플레이리스트 여부와 항목을 뽑는다.
    /// 단일 영상 URL이면 `isPlaylist == false`이고 entries는 비어 있다.
    static func playlistInfo(from jsonData: Data) -> PlaylistInfo? {
        guard let any = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] else {
            return nil
        }
        let type = (any["_type"] as? String) ?? ""
        let entriesRaw = any["entries"] as? [[String: Any]]
        let isPlaylist = type == "playlist" || (entriesRaw?.isEmpty == false)

        var entries: [PlaylistEntry] = []
        for e in entriesRaw ?? [] {
            // flat-playlist entry의 url은 단축형일 수 있어 _type/url 조합으로 복원
            let url = (e["url"] as? String)
                ?? (e["id"] as? String)   // 일부 추출기는 id만 주고 url은 플랫폼 기본 베이스로 조합 필요
            guard let url, !url.isEmpty else { continue }
            let title = (e["title"] as? String) ?? url
            let duration = (e["duration"] as? Double)
            entries.append(PlaylistEntry(url: url, title: title, durationSeconds: duration))
        }

        let count: Int? = {
            if let n = any["playlist_count"] as? Int { return n }
            if let s = any["playlist_count"] as? String, let n = Int(s) { return n }
            return nil
        }()

        return PlaylistInfo(isPlaylist: isPlaylist, count: count ?? entries.count, entries: entries)
    }
}
