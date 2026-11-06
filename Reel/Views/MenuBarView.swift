import SwiftUI

/// 화면 A — 메뉴바 팝오버.
///
/// 입력창 없이 클립보드로 동작한다:
/// - 팝오버 어디를 누르면 클립보드 링크가 큐에 추가된다 (⌘V와 동일)
/// 1. (있을 때만) 클립보드 감지 배너 / yt-dlp 미설치 배너
/// 2. 진행 중 항목 목록
/// 3. 푸터 — 완료 요약 · 저장 위치 · 설정 · 종료
struct MenuBarView: View {
    @Environment(QueueStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(ClipboardMonitor.self) private var clipboard
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var engineMissing: Bool { BinaryResolver.ytdlp == nil }

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
            }
            .frame(maxHeight: 460)

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

    // MARK: - 큐 리스트 (활성 항목만 — 메뉴바는 상태 요약이 목적)

    /// 진행 중인 항목만 표시. 완료·실패는 메인 윈도우에서 관리.
    private var activeTasks: [DownloadTask] {
        store.tasks.filter { $0.state.isActive }
    }

    @ViewBuilder private var queueList: some View {
        if activeTasks.isEmpty {
            VStack(spacing: Theme.s1) {
                Text("받은 항목이 여기에 표시됩니다")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.s4)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(activeTasks.enumerated()), id: \.element.id) { index, task in
                    if index > 0 {
                        Rectangle().fill(Theme.hairlineColor)
                            .frame(height: Theme.hairline)
                            .padding(.leading, 56)
                    }
                    MiniRow(task: task)
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

// MARK: - 미니 행 (호버 시 빠른 동작)

private struct MiniRow: View {
    @Environment(QueueStore.self) private var store
    let task: DownloadTask
    @State private var hovering = false

    var body: some View {
        HStack(spacing: Theme.s3) {
            Thumbnail(url: task.thumbnailURL, width: 46, height: 30,
                      duration: Fmt.duration(task.durationSeconds))
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                if task.state.isActive {
                    ThinProgressBar(value: task.progress,
                                    tint: task.state.tint,
                                    indeterminate: task.state == .encoding)
                }
                if let rt = task.retryText, task.state == .queued {
                    Text(rt)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: Theme.s1)
            trailing
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu { contextItems }
    }

    @ViewBuilder private var trailing: some View {
        switch task.state {
        case .downloading:
            if hovering {
                QuickIconButton(symbol: "xmark.circle", help: "취소") { store.cancel(task) }
            } else {
                Text("\(Int(task.progress * 100))%")
                    .font(Theme.rowMeta).monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        case .encoding:
            Text("변환 중")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.orange)
        case .completed:
            if hovering {
                QuickIconButton(symbol: "magnifyingglass", help: "Finder에서 보기") {
                    store.revealInFinder(task)
                }
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12)).foregroundStyle(.green)
            }
        case .failed:
            if hovering {
                QuickIconButton(symbol: "arrow.clockwise", help: "다시 시도") { store.retry(task) }
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11)).foregroundStyle(.red)
                    .help(task.errorMessage ?? "실패")
            }
        case .queued:
            if task.retryCount > 0 {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11)).foregroundStyle(.orange)
                    .help("일시적 오류 — 재시도 예정")
            } else {
                Text("대기")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        case .paused:
            if hovering {
                QuickIconButton(symbol: "play.circle", help: "재개") { store.resume(task) }
            } else {
                Image(systemName: "pause.circle").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        case .cancelled:
            Image(systemName: "xmark.circle").font(.system(size: 12)).foregroundStyle(.tertiary)
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
