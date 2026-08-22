import Foundation

/// 붙여넣기/드롭된 미디어 URL을 종류로 분류한다.
///
/// 채널·플레이리스트·단일 영상을 구분해 미리보기(채널 이름 + 영상 수)를
/// 정하는 데 사용한다. 네트워크 없이 URL 형태만으로 판별한다(빠름).
enum MediaLinkKind: Sendable {
    case single      // 단일 영상 (watch?v=, youtu.be/ID)
    case playlist     // 플레이리스트 (?list=)
    case channel       // 채널 (@handle, /channel/UC…)
    case other         // 그 외
}

struct MediaLink: Sendable {
    let raw: String
    let host: String
    let kind: MediaLinkKind

    /// URL 형태만으로 종류 분류.
    /// - 채널: `youtube.com/@핸들`, `youtube.com/channel/UC…`
    /// - 플레이리스트: `?list=`, `&list=`
    /// - 단일: `watch?v=`, `youtu.be/ID`
    init?(_ rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let u = URL(string: text),
              let scheme = u.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = u.host?.lowercased() else { return nil }
        self.raw = text
        self.host = host
        self.kind = Self.classify(host: host, path: u.path, query: u.query ?? "")
    }

    /// 채널 핸들 (`@원빅월드쇼` → `원빅월드쇼`). 없으면 nil.
    var channelHandle: String? {
        guard kind == .channel, let u = URL(string: raw) else { return nil }
        let p = u.path   // URL.path는 비옵셔널 String
        guard !p.isEmpty else { return nil }
        // /@핸들 → 핸들 (percent-decode)
        let trimmed = p.hasPrefix("/") ? String(p.dropFirst()) : p
        if trimmed.hasPrefix("@") {
            let handle = String(trimmed.dropFirst())
            // /videos 같은 하위 경로 제거
            let base = handle.split(separator: "/").first.map(String.init) ?? handle
            return base.removingPercentEncoding ?? base
        }
        return nil
    }

    /// 플레이리스트 ID (`?list=PL…` → `PL…`). 없으면 nil.
    var playlistID: String? {
        guard kind == .playlist,
              let u = URL(string: raw),
              let items = URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        return items.first(where: { $0.name == "list" })?.value
    }

    /// 플레이리스트/채널인지 여부.
    var isCollection: Bool {
        kind == .playlist || kind == .channel
    }

    /// 미리보기용 라벨 — 채널이면 핸들, 플레이리스트면 "플레이리스트", 그 외 "영상".
    var previewKindLabel: String {
        switch kind {
        case .channel: "채널"
        case .playlist: "플레이리스트"
        case .single: "영상"
        case .other: "링크"
        }
    }

    private static func classify(host: String, path: String, query: String) -> MediaLinkKind {
        let p = path.lowercased()

        // YouTube 계열
        if host == "youtu.be" || host.hasSuffix(".youtu.be") {
            // youtu.be/VIDEO_ID → 단일 (쿼리에 list= 있으면 플레이리스트)
            return query.contains("list=") ? .playlist : .single
        }
        if host == "youtube.com" || host.hasSuffix(".youtube.com") {
            // 채널: /@핸들, /channel/UC…
            if p.contains("/@") || p.contains("/channel/") || p.contains("/user/") {
                return .channel
            }
            // 플레이리스트: ?list=
            if query.contains("list=") {
                return .playlist
            }
            // 단일: /watch
            if p.contains("/watch") || p.contains("/shorts/") || p.contains("/embed/") {
                return .single
            }
            return .other
        }

        // 그 외 사이트: list= 쿼리가 있으면 플레이리스트로 추정
        if query.contains("list=") || p.contains("/playlist") {
            return .playlist
        }
        return .other
    }
}
