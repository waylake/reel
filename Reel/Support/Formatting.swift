import Foundation

enum Fmt {
    static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useMB, .useGB, .useKB]
        return f
    }()

    static func bytes(_ count: Int64?) -> String {
        guard let count, count > 0 else { return "" }
        return byteFormatter.string(fromByteCount: count)
    }

    static func bytes(_ count: Double?) -> String {
        guard let count, count > 0 else { return "" }
        return byteFormatter.string(fromByteCount: Int64(count))
    }

    /// 초 → "H:MM:SS" 또는 "M:SS"
    static func duration(_ seconds: Double?) -> String {
        guard let seconds, seconds > 0 else { return "" }
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%d:%02d", m, s)
    }

    static func resolutionLabel(width: Int?, height: Int?, vcodec: String?) -> String {
        var parts: [String] = []
        if let height { parts.append("\(height)p") }
        if let vcodec, !vcodec.isEmpty {
            parts.append(codecShortName(vcodec))
        }
        return parts.joined(separator: " · ")
    }

    static func codecShortName(_ vcodec: String) -> String {
        let c = vcodec.lowercased()
        if c.hasPrefix("avc1") || c.contains("h264") { return "H.264" }
        if c.hasPrefix("hev") || c.contains("h265") { return "H.265" }
        if c.hasPrefix("av01") || c.contains("av1") { return "AV1" }
        if c.contains("vp9") { return "VP9" }
        if c.contains("vp8") { return "VP8" }
        return vcodec
    }
}
