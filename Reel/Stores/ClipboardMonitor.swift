import AppKit
import Observation

/// 클립보드를 폴링해 붙여넣기 가능한 미디어 URL을 감지한다(기획서 화면 A).
@MainActor
@Observable
final class ClipboardMonitor {
    private(set) var detectedURL: String?

    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var lastHandledURL: String?
    private var timer: Timer?

    /// 사용자가 이미 처리(추가/무시)한 URL은 다시 배너로 띄우지 않는다.
    func markHandled(_ url: String) {
        lastHandledURL = url
        if detectedURL == url { detectedURL = nil }
    }

    func dismiss() {
        if let url = detectedURL { lastHandledURL = url }
        detectedURL = nil
    }

    func start() {
        guard timer == nil else { return }
        // 초기 진입 시 이미 복사돼 있던 URL도 한 번 확인
        checkPasteboard(force: true)
        let t = Timer(timeInterval: 0.6, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkPasteboard(force: false) }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func checkPasteboard(force: Bool) {
        let pb = NSPasteboard.general
        guard force || pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        guard let raw = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = Self.extractMediaURL(from: raw) else {
            return
        }
        guard url != lastHandledURL else { return }
        detectedURL = url
    }

    /// 문자열에서 http(s) URL을 추출하고, 미디어일 법한지 가볍게 판별.
    static func extractMediaURL(from text: String) -> String? {
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host?.lowercased() else { return nil }
        // 명백히 미디어가 아닌 경우를 넓게 허용하되 최소 검증만.
        let mediaHosts = ["youtube.com", "youtu.be", "vimeo.com", "twitch.tv",
                          "tiktok.com", "instagram.com", "x.com", "twitter.com",
                          "soundcloud.com", "bilibili.com", "dailymotion.com",
                          "facebook.com", "reddit.com", "nicovideo.jp"]
        if mediaHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
            return text
        }
        // 그 외 호스트도 경로가 있으면 허용(yt-dlp가 1800+ 사이트 지원).
        return url.path.count > 1 ? text : nil
    }
}
