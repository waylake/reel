import Foundation

/// 스마트 프리셋 — 기획서의 "포맷 & 품질" 기본값. 기본은 무손실 리먹스.
enum Preset: String, CaseIterable, Codable, Identifiable, Sendable {
    case bestMP4      // 최고 화질 → MP4로 리먹스(무손실)
    case hd1080       // 1080p 상한, 호환성 우선(H.264)
    case audioMP3     // 오디오만 · MP3
    case audioM4A     // 오디오만 · M4A(원본 AAC 추출)
    case original     // 원본 그대로(리먹스 없음)

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bestMP4: "최고 화질 (MP4)"
        case .hd1080: "1080p (호환성)"
        case .audioMP3: "오디오만 · MP3"
        case .audioM4A: "오디오만 · M4A"
        case .original: "원본 그대로"
        }
    }

    var shortTitle: String {
        switch self {
        case .bestMP4: "최고 화질"
        case .hd1080: "1080p"
        case .audioMP3: "MP3"
        case .audioM4A: "M4A"
        case .original: "원본"
        }
    }

    var symbol: String {
        switch self {
        case .bestMP4: "sparkles.tv"
        case .hd1080: "tv"
        case .audioMP3, .audioM4A: "music.note"
        case .original: "film"
        }
    }

    var isAudioOnly: Bool { self == .audioMP3 || self == .audioM4A }
}
