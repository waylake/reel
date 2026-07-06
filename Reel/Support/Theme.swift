import SwiftUI

/// Reel 디자인 토큰 — 전 화면이 이 규격만 사용한다. 매직넘버 금지.
///
/// 미학 원칙 (和の設え):
/// - 4pt 그리드: 모든 간격은 4의 배수. 리듬이 곧 통일감.
/// - 헤어라인(0.5pt): 면을 나눌 땐 두꺼운 선 대신 빛처럼 얇은 경계.
/// - 억제된 색: 무채색 바탕 + 상태색은 점(dot)과 칩에만. 액센트는 틸 하나.
/// - 모션은 짧고 조용하게(0.18s), reduced-motion 존중.
enum Theme {

    // MARK: - 간격 (4pt 그리드)

    /// 4 — 아이콘·텍스트 사이 최소 간격
    static let s1: CGFloat = 4
    /// 8 — 밀접한 형제 요소
    static let s2: CGFloat = 8
    /// 12 — 그룹 내부 패딩
    static let s3: CGFloat = 12
    /// 16 — 섹션 사이·컨테이너 패딩
    static let s4: CGFloat = 16
    /// 20 — 큰 구획
    static let s5: CGFloat = 20

    // MARK: - 반경

    /// 6 — 배지·작은 칩
    static let rSmall: CGFloat = 6
    /// 9 — 입력 필드·버튼
    static let rField: CGFloat = 9
    /// 11 — 행(row) 카드
    static let rRow: CGFloat = 11

    // MARK: - 선

    /// 헤어라인 두께
    static let hairline: CGFloat = 0.5
    /// 헤어라인 색 — 라이트/다크 자동
    static var hairlineColor: Color { Color.primary.opacity(0.08) }
    /// 행 카드 테두리
    static var rowBorder: Color { Color.primary.opacity(0.07) }
    /// 행 카드 바탕(휴지 상태)
    static var rowFill: Color { Color.primary.opacity(0.035) }
    /// 행 카드 바탕(호버)
    static var rowFillHover: Color { Color.primary.opacity(0.065) }
    /// 입력 필드 바탕
    static var fieldFill: Color { Color.primary.opacity(0.05) }

    // MARK: - 색

    /// 브랜드 액센트 — 앱 전체에서 단 하나.
    static let accent: Color = .teal

    // MARK: - 모션

    /// 표준 전환. reduce가 true면 nil(무애니메이션).
    static func motion(_ reduce: Bool) -> Animation? {
        reduce ? nil : .snappy(duration: 0.18)
    }
    /// 진행바 등 연속 값 갱신용.
    static func progressMotion(_ reduce: Bool) -> Animation? {
        reduce ? nil : .linear(duration: 0.25)
    }

    // MARK: - 타이포 (역할 기반)

    /// 행 제목
    static let rowTitle: Font = .system(size: 13, weight: .medium)
    /// 행 메타(숫자 포함 — 반드시 monospacedDigit와 함께)
    static let rowMeta: Font = .system(size: 11)
    /// 섹션 라벨 (uppercase 트래킹은 SectionLabel이 처리)
    static let sectionLabel: Font = .system(size: 10.5, weight: .semibold)
    /// 퍼센트 강조 숫자
    static let percent: Font = .system(size: 13, weight: .bold)
}

// MARK: - 공용 마이크로 컴포넌트

/// 섹션 라벨 — 소문자 금지, 자간으로 호흡.
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Theme.sectionLabel)
            .kerning(0.6)
            .foregroundStyle(.secondary)
    }
}

/// 3pt 두께 커스텀 진행바 — 시스템 ProgressView보다 조용하고 정밀.
struct ThinProgressBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var value: Double            // 0...1
    var tint: Color
    /// 인코딩 등 총량을 모르는 단계 — 은은한 펄스로 표현.
    var indeterminate: Bool = false

    @State private var pulse = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.14))
                if indeterminate {
                    Capsule()
                        .fill(tint.opacity(pulse ? 0.55 : 0.30))
                        .onAppear {
                            guard !reduceMotion else { pulse = true; return }
                            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                                pulse = true
                            }
                        }
                } else {
                    Capsule()
                        .fill(tint)
                        .frame(width: max(3, geo.size.width * min(1, max(0, value))))
                }
            }
        }
        .frame(height: 3)
        .animation(Theme.progressMotion(reduceMotion), value: value)
        .accessibilityElement()
        .accessibilityLabel(indeterminate ? "처리 중" : "진행률 \(Int(value * 100))퍼센트")
    }
}

/// 호버 시에만 또렷해지는 아이콘 버튼 — 행 안의 빠른 동작용.
struct QuickIconButton: View {
    let symbol: String
    let help: String
    var role: ButtonRole? = nil
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(hovering ? Color.primary : Color.secondary)
                .frame(width: 24, height: 24)
                .background(
                    Circle().fill(Color.primary.opacity(hovering ? 0.08 : 0))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// 상태 점 — 색 + 형태(채움/테두리)로 이중 인코딩.
struct StateDot: View {
    let state: DownloadState
    var body: some View {
        Circle()
            .fill(state.tint)
            .frame(width: 5, height: 5)
            .opacity(state == .queued || state == .paused ? 0.45 : 1)
    }
}
