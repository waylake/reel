import Foundation
import Observation

/// 사용자 기본 설정. @Observable로 UI 반영, UserDefaults로 영속화(persist() 호출).
@MainActor
@Observable
final class AppSettings {
    var defaultPreset: Preset
    var maxConcurrent: Int
    var outputDirectoryPath: String
    var autoDetectClipboard: Bool
    var notifyOnComplete: Bool
    var lowPowerProfile: Bool          // 배터리 프로필: 동시성↓ + 속도제한

    // 기본 부가 옵션
    var embedSubtitles: Bool
    var subtitleLangsText: String       // "ko,en"
    var autoSubtitles: Bool
    var embedChapters: Bool
    var embedMetadata: Bool
    var embedThumbnail: Bool
    var sponsorBlock: Bool
    var cookiesFromBrowser: String      // "" | "safari" | "chrome" | "firefox"
    var includeVideoID: Bool            // 파일명에 [영상 ID] 포함 여부 (기본: 제목만)

    private static let key = "reel.settings.v1"

    init() {
        let d = UserDefaults.standard.data(forKey: Self.key)
        let s = d.flatMap { try? JSONDecoder().decode(Stored.self, from: $0) } ?? .default
        defaultPreset = Preset(rawValue: s.defaultPreset) ?? .bestMP4
        maxConcurrent = s.maxConcurrent
        outputDirectoryPath = s.outputDirectoryPath.isEmpty ? URL.moviesReel.path : s.outputDirectoryPath
        autoDetectClipboard = s.autoDetectClipboard
        notifyOnComplete = s.notifyOnComplete
        lowPowerProfile = s.lowPowerProfile
        embedSubtitles = s.embedSubtitles
        subtitleLangsText = s.subtitleLangsText
        autoSubtitles = s.autoSubtitles
        embedChapters = s.embedChapters
        embedMetadata = s.embedMetadata
        embedThumbnail = s.embedThumbnail
        sponsorBlock = s.sponsorBlock
        cookiesFromBrowser = s.cookiesFromBrowser
        includeVideoID = s.includeVideoID ?? false
    }

    var outputDirectory: URL {
        URL(fileURLWithPath: outputDirectoryPath, isDirectory: true)
    }

    /// 저전력 프로필을 반영한 실효 동시성.
    var effectiveConcurrency: Int {
        lowPowerProfile ? min(2, maxConcurrent) : maxConcurrent
    }

    /// 설정 + 프리셋으로 다운로드 옵션 조립.
    func makeOptions(preset: Preset) -> DownloadOptions {
        var o = DownloadOptions()
        o.preset = preset
        o.embedSubtitles = embedSubtitles
        o.subtitleLangs = subtitleLangsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if o.subtitleLangs.isEmpty { o.subtitleLangs = ["ko", "en"] }
        o.autoSubtitles = autoSubtitles
        o.embedChapters = embedChapters
        o.embedMetadata = embedMetadata
        o.embedThumbnail = embedThumbnail
        o.sponsorBlock = sponsorBlock
        o.cookiesFromBrowser = cookiesFromBrowser.isEmpty ? nil : cookiesFromBrowser
        o.outputDirectory = outputDirectory
        o.outputTemplate = includeVideoID ? "%(title)s [%(id)s].%(ext)s" : "%(title)s.%(ext)s"
        o.concurrentFragments = lowPowerProfile ? 2 : 4
        o.limitRate = lowPowerProfile ? "8M" : nil
        return o
    }

    func persist() {
        let s = Stored(
            defaultPreset: defaultPreset.rawValue,
            maxConcurrent: maxConcurrent,
            outputDirectoryPath: outputDirectoryPath,
            autoDetectClipboard: autoDetectClipboard,
            notifyOnComplete: notifyOnComplete,
            lowPowerProfile: lowPowerProfile,
            embedSubtitles: embedSubtitles,
            subtitleLangsText: subtitleLangsText,
            autoSubtitles: autoSubtitles,
            embedChapters: embedChapters,
            embedMetadata: embedMetadata,
            embedThumbnail: embedThumbnail,
            sponsorBlock: sponsorBlock,
            cookiesFromBrowser: cookiesFromBrowser,
            includeVideoID: includeVideoID
        )
        if let data = try? JSONEncoder().encode(s) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    private struct Stored: Codable {
        var defaultPreset: String
        var maxConcurrent: Int
        var outputDirectoryPath: String
        var autoDetectClipboard: Bool
        var notifyOnComplete: Bool
        var lowPowerProfile: Bool
        var embedSubtitles: Bool
        var subtitleLangsText: String
        var autoSubtitles: Bool
        var embedChapters: Bool
        var embedMetadata: Bool
        var embedThumbnail: Bool
        var sponsorBlock: Bool
        var cookiesFromBrowser: String
        var includeVideoID: Bool? = false   // 옵셔널: 구버전 JSON과 호환

        static let `default` = Stored(
            defaultPreset: Preset.bestMP4.rawValue,
            maxConcurrent: 3,
            outputDirectoryPath: "",
            autoDetectClipboard: true,
            notifyOnComplete: true,
            lowPowerProfile: false,
            embedSubtitles: false,
            subtitleLangsText: "ko,en",
            autoSubtitles: false,
            embedChapters: true,
            embedMetadata: true,
            embedThumbnail: false,
            sponsorBlock: false,
            cookiesFromBrowser: "",
            includeVideoID: false
        )
    }
}
