import SwiftUI

/// 화면 B의 큐 항목 행.
///
/// 디테일 규칙:
/// - 상태는 색·점·텍스트 삼중 인코딩 (StateChip)
/// - 호버하면 바탕이 미세하게 밝아지고, 그 상태에서 유효한 빠른 동작만 나타남
/// - 숫자는 전부 tabular(자릿수 정렬), 진행바는 3pt 헤어라인 감성
/// - 실패 행은 에러 요지를 그 자리에서 보여주고, 전문은 툴팁으로
struct DownloadRowView: View {
    @Environment(QueueStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let task: DownloadTask

    @State private var hovering = false

    var body: some View {
        HStack(spacing: Theme.s3) {
            Thumbnail(url: task.thumbnailURL, width: 66, height: 40,
                      duration: Fmt.duration(task.durationSeconds))

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(Theme.rowTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)

                metaLine

                if task.state.isActive {
                    ThinProgressBar(value: task.progress,
                                    tint: task.state.tint,
                                    indeterminate: task.state == .encoding)
                        .padding(.top, 3)
                }

                if task.state == .failed, let message = task.errorMessage {
                    Text(errorSummary(message))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.red)
                        .lineLimit(1)
                        .help(message)   // 전문은 툴팁으로
                }
            }

            Spacer(minLength: Theme.s2)

            // 우측: 퍼센트 + 상태 칩 (호버 시 빠른 동작으로 교체)
            if hovering {
                quickActions
                    .transition(.opacity)
            } else {
                VStack(alignment: .trailing, spacing: Theme.s1) {
                    if task.state == .downloading {
                        Text("\(Int(task.progress * 100))%")
                            .font(Theme.percent).monospacedDigit()
                    }
                    StateChip(state: task.state)
                }
                .transition(.opacity)
            }
        }
        .padding(Theme.s3)
        .background(
            RoundedRectangle(cornerRadius: Theme.rRow, style: .continuous)
                .fill(hovering ? Theme.rowFillHover : Theme.rowFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.rRow, style: .continuous)
                .strokeBorder(Theme.rowBorder, lineWidth: Theme.hairline)
        )
        .contentShape(RoundedRectangle(cornerRadius: Theme.rRow, style: .continuous))
        .onHover { hovering = $0 }
        .animation(Theme.motion(reduceMotion), value: hovering)
        .contextMenu { contextItems }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(task.title), \(task.state.label)")
    }

    // MARK: - 메타 라인 (상태별 분기)

    @ViewBuilder private var metaLine: some View {
        HStack(spacing: Theme.s2) {
            switch task.state {
            case .downloading:
                if !task.sizeText.isEmpty { Text(task.sizeText) }
                if !task.speedText.isEmpty { Text(task.speedText) }
                if !task.etaText.isEmpty {
                    Text("남은 시간 \(task.etaText)")
                }
            case .encoding:
                Text("후처리 중 — 병합·변환")
            case .completed:
                if !task.metaSubtitle.isEmpty { Text(task.metaSubtitle) }
                if let path = task.outputPath {
                    Text(URL(fileURLWithPath: path).lastPathComponent)
                        .lineLimit(1).truncationMode(.middle)
                }
            case .queued:
                Text("대기 중 · \(task.options.preset.title)")
            case .paused:
                Text("일시정지됨 · \(Int(task.progress * 100))%까지 받음")
            default:
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
