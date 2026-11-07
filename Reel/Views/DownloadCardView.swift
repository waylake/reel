import SwiftUI

/// 화면 B의 큐 항목 카드 — 메인 윈도우 그리드의 한 칸.
///
/// 구성 (위→아래):
/// 1. 16:9 썸네일 — 우하단 길이 배지, 호버 시 우상단에 빠른 동작
/// 2. 진행바 (진행 중일 때만)
/// 3. 제목 2줄
/// 4. 메타 라인 + 상태 칩 / 퍼센트
///
/// 디테일 규칙:
/// - 상태는 색·점·텍스트 삼중 인코딩 (StateChip)
/// - 호버하면 바탕이 미세하게 밝아지고, 그 상태에서 유효한 빠른 동작만 나타남
/// - 숫자는 전부 tabular(자릿수 정렬)
/// - 실패 카드는 에러 요지를 그 자리에서 보여주고, 전문은 툴팁으로
struct DownloadCardView: View {
    @Environment(QueueStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let task: DownloadTask

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s2) {
            thumbnail

            // 진행바 자리는 항상 확보 — 상태가 달라도 같은 줄 카드 높이가 맞도록.
            ThinProgressBar(value: task.progress,
                            tint: task.state.tint,
                            indeterminate: task.state == .encoding)
                .opacity(task.state.isActive ? 1 : 0)
                .accessibilityHidden(!task.state.isActive)

            Text(task.title)
                .font(Theme.rowTitle)
                .lineLimit(2, reservesSpace: true)
                .truncationMode(.tail)
                .help(task.title)

            HStack(alignment: .firstTextBaseline, spacing: Theme.s2) {
                metaLine
                Spacer(minLength: Theme.s1)
                if task.state == .downloading {
                    Text("\(Int(task.progress * 100))%")
                        .font(Theme.percent).monospacedDigit()
                } else {
                    StateChip(state: task.state)
                }
            }

            if task.state == .failed, let message = task.errorMessage {
                Text(errorSummary(message))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .help(message)   // 전문은 툴팁으로
            }
        }
        .padding(Theme.s2)
        .background(
            RoundedRectangle(cornerRadius: Theme.rRow, style: .continuous)
                .fill(hovering ? Theme.rowFillHover : Theme.fieldFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.rRow, style: .continuous)
                .strokeBorder(Theme.hairlineColor, lineWidth: Theme.hairline)
        )
        .contentShape(RoundedRectangle(cornerRadius: Theme.rRow, style: .continuous))
        .onTapGesture(count: 2) { if task.state == .completed { store.openFile(task) } }
        .onHover { hovering = $0 }
        .animation(Theme.motion(reduceMotion), value: hovering)
        .contextMenu { contextItems }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(task.title), \(task.state.label)")
    }

    // MARK: - 썸네일 (폭에 맞춰 16:9)

    private var thumbnail: some View {
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    Thumbnail(url: task.thumbnailURL,
                              width: geo.size.width, height: geo.size.height,
                              duration: Fmt.duration(task.durationSeconds))
                }
            }
            .overlay(alignment: .topTrailing) {
                if hovering {
                    quickActions
                        .padding(Theme.s1)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(Theme.s1)
                        .transition(.opacity)
                }
            }
    }

    // MARK: - 메타 라인 (상태별 분기 — 결정은 DownloadTask.metaPhase가, 렌더링만 여기서)

    @ViewBuilder private var metaLine: some View {
        HStack(spacing: Theme.s2) {
            switch task.metaPhase {
            case .extracting:
                // 추출 단계(웨이브페이지·player API 수신 중) — 바이트가 흐르기 전이라
                // 0%로 멈춰 보이던 문제. (#11)
                Text("영상 정보 가져오는 중…")
            case .downloading(let size, let speed, let eta):
                if !size.isEmpty { Text(size) }
                if !speed.isEmpty { Text(speed) }
                if !eta.isEmpty { Text(eta) }
            case .encoding:
                Text("병합·변환 중")
            case .completed(let subtitle):
                if !subtitle.isEmpty { Text(subtitle) }
            case .waiting(let retry):
                if let retry {
                    Text(retry)
                } else {
                    Text(task.options.preset.title)
                }
            case .paused(let percent):
                Text("\(percent)%까지 받음")
            case .failed:
                if !task.metaSubtitle.isEmpty { Text(task.metaSubtitle) }
            }
        }
        .font(Theme.rowMeta).monospacedDigit()
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    // MARK: - 호버 빠른 동작 (상태별로 유효한 것만)

    @ViewBuilder private var quickActions: some View {
        HStack(spacing: Theme.s1) {
            switch task.state {
            case .downloading:
                QuickIconButton(symbol: "pause.fill", help: "일시정지") { store.pause(task) }
                QuickIconButton(symbol: "xmark", help: "취소") { store.cancel(task) }
            case .paused:
                QuickIconButton(symbol: "play.fill", help: "재개") { store.resume(task) }
                QuickIconButton(symbol: "xmark", help: "취소") { store.cancel(task) }
            case .encoding:
                QuickIconButton(symbol: "xmark", help: "취소") { store.cancel(task) }
            case .queued:
                QuickIconButton(symbol: "xmark", help: "대기열에서 제거") { store.cancel(task) }
            case .completed:
                QuickIconButton(symbol: "play.fill", help: "열기") { store.openFile(task) }
                QuickIconButton(symbol: "magnifyingglass", help: "Finder에서 보기") { store.revealInFinder(task) }
            case .failed, .cancelled:
                QuickIconButton(symbol: "arrow.clockwise", help: "다시 시도") { store.retry(task) }
                QuickIconButton(symbol: "trash", help: "목록에서 제거") { store.remove(task) }
            }
        }
    }

    // MARK: - 컨텍스트 메뉴 (우클릭)

    @ViewBuilder private var contextItems: some View {
        if task.state == .downloading { Button("일시정지") { store.pause(task) } }
        if task.state == .paused { Button("재개") { store.resume(task) } }
        if task.state.isActive || task.state == .paused || task.state == .queued {
            Button("취소") { store.cancel(task) }
        }
        if task.state.isRestartable { Button("다시 시도") { store.retry(task) } }
        if task.state == .completed {
            Button("열기") { store.openFile(task) }
            Button("Finder에서 보기") { store.revealInFinder(task) }
        }
        Button("원본 링크 복사") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(task.url, forType: .string)
        }
        Divider()
        Button("목록에서 제거", role: .destructive) { store.remove(task) }
    }

    /// 긴 yt-dlp 에러에서 사람에게 유의미한 첫 줄만.
    private func errorSummary(_ message: String) -> String {
        let lines = message.split(whereSeparator: \.isNewline)
        if let errorLine = lines.first(where: { $0.contains("ERROR") }) {
            return String(errorLine).replacingOccurrences(of: "ERROR: ", with: "")
        }
        return String(lines.first ?? "알 수 없는 오류")
    }
}
