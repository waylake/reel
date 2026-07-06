import Foundation

/// yt-dlp 프로세스가 내보내는 이벤트. UI는 이 스트림을 소비해 상태를 갱신한다.
enum EngineEvent: Sendable {
    case started
    case phase(DownloadState)                       // 예: 후처리 → .encoding
    case progress(fraction: Double, speed: String, eta: String, downloaded: Int64, total: Int64?)
    case destination(String)
    case finalFile(String)
    case completed
    case cancelled
    case failed(String)
}

/// stdout 한 줄 → 0개 이상의 이벤트로 변환하는 순수 함수 모음.
enum ProgressParser {
    static func parse(line rawLine: String) -> [EngineEvent] {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return [] }
        let s = ArgumentBuilder.sentinel

        if line.hasPrefix(s) {
            let body = String(line.dropFirst(s.count))
            if body.hasPrefix("FILE|") {
                let path = String(body.dropFirst("FILE|".count))
                return path.isEmpty || path == "NA" ? [] : [.finalFile(path)]
            }
            let parts = body.components(separatedBy: "|")
            guard parts.count >= 3 else { return [] }
            let fraction = percentToFraction(parts[0])
            let speed = clean(parts[1])
            let eta = clean(parts[2])
            let downloaded = parts.count > 3 ? Int64(clean(parts[3])) ?? 0 : 0
            let total = parts.count > 4 ? Int64(clean(parts[4])) : nil
            return [.progress(fraction: fraction, speed: speed, eta: eta, downloaded: downloaded, total: total)]
        }

        // 후처리(병합/변환/추출/자막/스폰서블록) 단계 감지 → 인코딩 상태
        for marker in ["[Merger]", "[VideoConvertor]", "[ExtractAudio]",
                       "[VideoRemuxer]", "[Metadata]", "[EmbedSubtitle]", "[SponsorBlock]"] {
            if line.contains(marker) { return [.phase(.encoding)] }
        }

        if let r = line.range(of: "[download] Destination: ") {
            return [.destination(String(line[r.upperBound...]))]
        }
        return []
    }

    private static func percentToFraction(_ raw: String) -> Double {
        let t = raw.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
        guard let v = Double(t) else { return 0 }
        return min(1, max(0, v / 100))
    }

    private static func clean(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespaces)
        return (t == "Unknown" || t == "NA" || t == "N/A") ? "" : t
    }
}
