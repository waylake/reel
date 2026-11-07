import SwiftUI

/// 화면 A — 메뉴바 팝오버.
///
/// 입력창 없이 클립보드로 동작한다:
/// - 팝오버 어디를 누르면 클립보드 링크가 큐에 추가된다 (⌘V와 동일)
/// 1. (있을 때만) 클립보드 감지 배너 / yt-dlp 미설치 배너
/// 2. 썸네일 카드 — 진행 중 항목 + 최근 완료 3개
/// 3. 푸터 — 완료 요약 · 저장 위치 · 설정 · 종료
struct MenuBarView: View {
    @Environment(QueueStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(ClipboardMonitor.self) private var clipboard
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var engineMissing: Bool { BinaryResolver.ytdlp == nil }

    /// 스크롤 내용의 실제 높이. 팝오버는 ScrollView의 이상적 높이를 0으로 잡을 수 있어
    /// 측정값으로 높이를 정하고 최대 높이를 넘으면 스크롤한다.
    @State private var contentHeight: CGFloat = 0
    private let maxListHeight: CGFloat = 520

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.s3) {
                    if engineMissing {
                        SetupBanner()
                    }
                    if settings.autoDetectClipboard, let detected = clipboard.detectedURL {
                        clipboardBanner(detected)
                            .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)),
                                                    removal: .opacity))
                    }
                    queueList
                }
                .padding(Theme.s3)
                .animation(Theme.motion(reduceMotion), value: clipboard.detectedURL)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .frame(height: min(max(contentHeight, 1), maxListHeight))

            Rectangle().fill(Theme.hairlineColor).frame(height: Theme.hairline)
            footer
        }
        .contentShape(Rectangle())
        .onTapGesture { pasteFromClipboard() }   // 어디를 누르든 클립보드 링크 추가
    }

    // MARK: - 클립보드 배너 (일반 / 중복 분기)

    @ViewBuilder
    private func clipboardBanner(_ url: String) -> some View {
        let duplicate = store.activeDuplicate(of: url)
        HStack(spacing: Theme.s3) {
            Image(systemName: duplicate == nil ? "doc.on.clipboard" : "checkmark.circle")
                .foregroundStyle(duplicate == nil ? Theme.accent : .green)
                .font(.system(size: 13))
            VStack(alignment: .leading, spacing: 2) {
                Text(duplicate == nil ? "복사된 링크 감지" : "이미 큐에 있는 링크")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(url)
                    .font(.system(size: 12))
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: Theme.s2)
            if duplicate == nil {
                Button("추가") { add(url: url) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(Theme.accent)
            } else {
                Button("보기") { openMainWindow() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            QuickIconButton(symbol: "xmark", help: "이 링크 무시") {
                clipboard.dismiss()
            }
        }
        .padding(Theme.s3)
        .background(
            (duplicate == nil ? Theme.accent : Color.green).opacity(0.08),
            in: RoundedRectangle(cornerRadius: Theme.rField, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.rField, style: .continuous)
                .strokeBorder((duplicate == nil ? Theme.accent : Color.green).opacity(0.18),
                              lineWidth: Theme.hairline)
        )
    }

    // MARK: - 카드 목록 (진행 중 + 최근 완료)

    /// 진행 중·대기·일시정지 항목. 실패·취소는 메인 윈도우에서 관리.
    private var activeTasks: [DownloadTask] {
        store.tasks.filter { $0.state.isActive || $0.state == .queued || $0.state == .paused }
    }

    /// 최근 완료 3개 — 팝오버를 열었을 때 방금 받은 것을 썸네일로 바로 확인.
    private var recentCompleted: [DownloadTask] {
        store.tasks
            .filter { $0.state == .completed }
            .sorted { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) }
            .prefix(3)
            .map { $0 }
    }

    @ViewBuilder private var queueList: some View {
        if activeTasks.isEmpty && recentCompleted.isEmpty {
            VStack(spacing: Theme.s2) {
                Image(systemName: "arrow.down.circle.dotted")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("링크를 복사한 뒤 여기를 누르세요")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.s4 * 2)
        } else {
            VStack(alignment: .leading, spacing: Theme.s2) {
                ForEach(activeTasks) { task in
                    MiniCard(task: task)
                }
                if !recentCompleted.isEmpty {
                    Text("최근 받은 항목")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, activeTasks.isEmpty ? 0 : Theme.s2)
                        .padding(.leading, Theme.s1)
                    ForEach(recentCompleted) { task in
                        MiniCard(task: task)
                    }
                }
            }
        }
    }

    // MARK: - 푸터

    private var footer: some View {
        HStack(spacing: Theme.s3) {
            // 완료 요약 — 누르면 메인 윈도우를 연다. 완료 목록은 거기서 본다.
            Button { openMainWindow() } label: {
                Label("완료 \(store.completedCount)개", systemImage: "checkmark.circle")
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .help("메인 윈도우 열기")

            Spacer()

            Text(destinationName)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .help("저장 위치: \(settings.outputDirectoryPath)")

            Spacer()

            SettingsLink {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .help("설정 (⌘,)")

            Button {
                store.save()
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .help("Reel 종료")
        }
        .padding(.horizontal, Theme.s3)
        .padding(.vertical, 8)
    }

    private var destinationName: String {
        "→ " + (settings.outputDirectory.lastPathComponent)
    }

    // MARK: - 동작

    /// 아무 곳이나 누르면 클립보드 링크를 큐에 추가. 링크가 없으면 비프음.
    /// 프리셋·플레이리스트 모드는 설정(기본값)을 따른다 — 여기서는 고르지 않는다.
    private func pasteFromClipboard() {
        if let task = store.addFromPasteboard() {
            clipboard.markHandled(task.url)
        } else {
            NSSound.beep()
        }
    }

    /// 클립보드 배너의 "추가" 버튼.
    private func add(url raw: String) {
        guard let url = ClipboardMonitor.extractMediaURL(from: raw) else { return }
        clipboard.markHandled(url)
        store.add(url: url)
    }

    private func openMainWindow() {
        (NSApp.delegate as? AppDelegate)?.showMainWindow()
    }
}

// MARK: - yt-dlp 미설치 온보딩

private struct SetupBanner: View {
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s2) {
            Label("yt-dlp가 필요해요", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)
            Text("터미널에서 아래 명령으로 설치하면 바로 사용할 수 있어요.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack {
                Text("brew install yt-dlp ffmpeg")
                    .font(.system(size: 11, design: .monospaced))
                Spacer()
                Button(copied ? "복사됨 ✓" : "복사") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("brew install yt-dlp ffmpeg", forType: .string)
                    copied = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                }
                .controlSize(.small)
            }
            .padding(Theme.s2)
            .background(Theme.fieldFill, in: RoundedRectangle(cornerRadius: Theme.rSmall))
        }
        .padding(Theme.s3)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.rField, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.rField, style: .continuous)
                .strokeBorder(.orange.opacity(0.2), lineWidth: Theme.hairline)
        )
    }
}

// MARK: - 미니 카드 (메인 윈도우 카드의 가로형 축소판)

/// 썸네일(16:9) + 제목 2줄 + 진행바/메타. 호버하면 썸네일 위에 빠른 동작이 뜬다.
/// 카드 클릭은 팝오버의 "클릭하면 클립보드 링크 추가"로 새지 않게 여기서 소비한다.
private struct MiniCard: View {
    @Environment(QueueStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let task: DownloadTask
    @State private var hovering = false

    var body: some View {
        HStack(spacing: Theme.s3) {
            Thumbnail(url: task.thumbnailURL, width: 96, height: 54,
                      duration: Fmt.duration(task.durationSeconds))
                .opacity(task.state == .queued ? 0.55 : 1)
                .overlay {
                    if hovering, let action = primaryAction {
                        QuickIconButton(symbol: action.symbol, help: action.help, action: action.run)
                            .background(.ultraThinMaterial, in: Circle())
                            .transition(.opacity)
                    }
                }

            VStack(alignment: .leading, spacing: Theme.s1) {
                Text(task.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
                Spacer(minLength: 0)
                if task.state.isActive {
                    ThinProgressBar(value: task.progress,
                                    tint: task.state.tint,
                                    indeterminate: task.state == .encoding)
                }
                meta
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 54)
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
        .onTapGesture { if task.state == .completed { store.openFile(task) } }
        .onHover { hovering = $0 }
        .animation(Theme.motion(reduceMotion), value: hovering)
        .contextMenu { contextItems }
        .help(task.state == .completed ? "클릭하면 열기" : "")
    }

    /// 상태별 한 줄 — 진행 중이면 퍼센트·속도·남은 시간, 완료면 크기, 그 외엔 상태 칩.
    @ViewBuilder private var meta: some View {
        HStack(spacing: Theme.s2) {
            switch task.metaPhase {
            case .downloading(_, let speed, let eta):
                Text("\(Int(task.progress * 100))%").fontWeight(.semibold).foregroundStyle(.primary)
                if !speed.isEmpty { Text(speed) }
                Spacer(minLength: 0)
                if !eta.isEmpty { Text(eta) }
            case .extracting:
                Text("영상 정보 가져오는 중…")
            case .encoding:
                Text("병합·변환 중").foregroundStyle(.orange)
            case .completed(let subtitle):
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                if !subtitle.isEmpty { Text(subtitle) }
            case .waiting(let retry):
                if let retry { Text(retry).foregroundStyle(.orange) }
            case .paused(let percent):
                Image(systemName: "pause.circle")
                Text("\(percent)%")
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    .help(task.errorMessage ?? "실패")
            }
        }
        .font(.system(size: 10.5)).monospacedDigit()
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    /// 호버 시 썸네일 위에 뜨는 대표 동작 하나.
    private var primaryAction: (symbol: String, help: String, run: () -> Void)? {
        switch task.state {
        case .downloading: ("pause.fill", "일시정지", { store.pause(task) })
        case .paused: ("play.fill", "재개", { store.resume(task) })
        case .encoding, .queued: ("xmark", "취소", { store.cancel(task) })
        case .completed: ("magnifyingglass", "Finder에서 보기", { store.revealInFinder(task) })
        case .failed, .cancelled: ("arrow.clockwise", "다시 시도", { store.retry(task) })
        }
    }

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
        Divider()
        Button("목록에서 제거", role: .destructive) { store.remove(task) }
    }
}
