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
}
