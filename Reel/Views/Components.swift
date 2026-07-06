import SwiftUI

/// 썸네일 — 비동기 로드 + 우하단 길이 배지(유튜브 관례).
struct Thumbnail: View {
    let url: URL?
    var width: CGFloat
    var height: CGFloat
    var duration: String? = nil   // "12:34" — 있으면 배지 표시

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.rSmall, style: .continuous)
            .fill(LinearGradient(colors: [Color(white: 0.28), Color(white: 0.15)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                if let url {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                                .transition(.opacity)
                        case .failure:
                            placeholderIcon
                        default:
                            // 로딩 중 — 스켈레톤 대신 조용한 바탕 유지
                            Color.clear
                        }
                    }
                } else {
                    placeholderIcon
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let duration, !duration.isEmpty {
                    Text(duration)
                        .font(.system(size: 9, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4).padding(.vertical, 1.5)
                        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 3))
                        .padding(3)
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: Theme.rSmall, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.rSmall, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: Theme.hairline)
            )
            .accessibilityHidden(true)
    }

    private var placeholderIcon: some View {
        Image(systemName: "film")
            .font(.system(size: min(width, height) * 0.32))
            .foregroundStyle(.white.opacity(0.22))
    }
}

/// 상태 칩 — 점(형태) + 텍스트(내용) + 색의 삼중 인코딩. 색약에도 읽힌다.
struct StateChip: View {
    let state: DownloadState
    var body: some View {
        HStack(spacing: Theme.s1) {
            StateDot(state: state)
            Text(state.label)
                .font(.system(size: 10, weight: .semibold))
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .foregroundStyle(state.tint)
        .background(state.tint.opacity(0.13), in: Capsule())
        .accessibilityLabel("상태: \(state.label)")
    }
}
