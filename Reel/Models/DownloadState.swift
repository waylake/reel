import Foundation
import SwiftUI

/// 다운로드 항목의 생명주기 상태. 화면에서 색 + 칩으로 이중 인코딩된다.
enum DownloadState: String, Codable, CaseIterable, Sendable {
    case queued        // 대기
    case downloading   // 받는 중
    case encoding      // 병합/변환 (후처리)
    case completed     // 완료
    case failed        // 실패
    case paused        // 일시정지
    case cancelled     // 취소됨

    var label: String {
        switch self {
        case .queued: "대기"
        case .downloading: "받는 중"
        case .encoding: "인코딩"
        case .completed: "완료"
        case .failed: "실패"
        case .paused: "일시정지"
        case .cancelled: "취소됨"
        }
    }

    var symbol: String {
        switch self {
        case .queued: "clock"
        case .downloading: "arrow.down.circle"
        case .encoding: "wand.and.stars"
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .paused: "pause.circle"
        case .cancelled: "xmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .queued, .paused: .secondary
        case .downloading: .teal
        case .encoding: .orange
        case .completed: .green
        case .failed, .cancelled: .red
        }
    }

    /// 활성(코어 점유) 상태인지 — 동시성 스케줄러가 사용.
    var isActive: Bool { self == .downloading || self == .encoding }

    /// 다시 시작 가능한 종료 상태인지.
    var isRestartable: Bool { self == .failed || self == .cancelled || self == .paused }
}
