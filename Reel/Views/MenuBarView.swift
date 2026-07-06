import SwiftUI

/// 화면 A — 메뉴바 팝오버. 앱의 주 진입점.
///
/// 상태 분기:
/// 1. yt-dlp 미설치 → 온보딩 배너 (설치 명령 복사)
/// 2. 클립보드에 새 링크 → 감지 배너 / 이미 큐에 있으면 "추가됨" 변형
/// 3. 입력 텍스트가 링크가 아님 → 조용한 힌트
/// 4. 추가 직후 → 버튼이 "추가됨 ✓"로 1.2초 변형
/// 5. 큐 비어 있음 → 안내 문구 / 있음 → 미니 큐(호버 시 빠른 동작)
struct MenuBarView: View {
    @Environment(QueueStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(ClipboardMonitor.self) private var clipboard
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var urlText = ""
    @State private var preset: Preset = .bestMP4
    @State private var justAdded = false
    @FocusState private var fieldFocused: Bool

    private var engineMissing: Bool { BinaryResolver.ytdlp == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Theme.hairlineColor).frame(height: Theme.hairline)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.s4) {
                    if engineMissing {
                        SetupBanner()
                    }
                    if settings.autoDetectClipboard, let detected = clipboard.detectedURL {
                        clipboardBanner(detected)
                            .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)),
                                                    removal: .opacity))
                    }
                    inputSection
                    queueSection
                }
                .padding(Theme.s4)
                .animation(Theme.motion(reduceMotion), value: clipboard.detectedURL)
            }
            .frame(maxHeight: 430)

            Rectangle().fill(Theme.hairlineColor).frame(height: Theme.hairline)
            footer
        }
        .onAppear { preset = settings.defaultPreset }
    }

    // MARK: - 헤더

    private var header: some View {
        HStack(spacing: Theme.s2) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(Theme.accent)
                .font(.system(size: 14, weight: .semibold))
            Text("Reel").font(.system(size: 14, weight: .bold))
            Spacer()
            // 활동 요약 — 진행 중일 때만 조용히 표시
            if store.activeCount > 0 {
                HStack(spacing: Theme.s1) {
                    StateDot(state: .downloading)
                    Text("\(store.activeCount) 진행 중")
                        .font(Theme.rowMeta).monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            } else if store.completedToday > 0 {
                Text("오늘 \(store.completedToday)개 완료")
                    .font(Theme.rowMeta).monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, Theme.s4)
        .padding(.vertical, Theme.s3)
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

    // MARK: - 입력

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: Theme.s2) {
            HStack(spacing: Theme.s2) {
                Image(systemName: "link")
                    .font(.system(size: 11))
                    .foregroundStyle(fieldFocused ? Theme.accent : .secondary)
                TextField("링크 붙여넣기", text: $urlText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .focused($fieldFocused)
                    .onSubmit { add(url: urlText) }
            }
            .padding(.horizontal, Theme.s3)
            .padding(.vertical, 9)
            .background(Theme.fieldFill, in: RoundedRectangle(cornerRadius: Theme.rField, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.rField, style: .continuous)
                    .strokeBorder(fieldFocused ? Theme.accent.opacity(0.5) : Color.clear, lineWidth: 1)
            )
            .animation(Theme.motion(reduceMotion), value: fieldFocused)

            // 잘못된 링크 힌트 — 비어 있지 않은데 URL이 아닐 때만
            if !urlText.isEmpty && inputURL == nil {
                Label("지원하는 링크 형식이 아니에요", systemImage: "info.circle")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.orange)
                    .transition(.opacity)
            }

            HStack(spacing: Theme.s2) {
                Picker("프리셋", selection: $preset) {
                    ForEach(Preset.allCases) { p in
                        Label(p.shortTitle, systemImage: p.symbol).tag(p)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .fixedSize()
                .help("저장 품질 프리셋")

                Spacer()

                Button {
                    add(url: urlText.isEmpty ? (clipboard.detectedURL ?? "") : urlText)
                } label: {
                    Label(justAdded ? "추가됨" : "저장",
                          systemImage: justAdded ? "checkmark" : "arrow.down")
                        .frame(minWidth: 64)
                }
                .buttonStyle(.borderedProminent)
                .tint(justAdded ? .green : Theme.accent)
                .disabled(currentInputURL == nil && !justAdded)
                .keyboardShortcut(.defaultAction)
                .animation(Theme.motion(reduceMotion), value: justAdded)
            }
        }
        .animation(Theme.motion(reduceMotion), value: urlText.isEmpty)
    }

    // MARK: - 미니 큐

    @ViewBuilder
    private var queueSection: some View {
        if store.recent.isEmpty {
            // 빈 상태 — 첫 사용 안내는 짧게, 조용하게
            VStack(spacing: Theme.s1) {
                Text("받은 항목이 여기에 표시됩니다")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.s4)
        } else {
            VStack(alignment: .leading, spacing: Theme.s1) {
                HStack {
                    SectionLabel(text: "최근")
                    Spacer()
                    Button("전체 보기") { openMainWindow() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.accent)
                }
                VStack(spacing: 0) {
                    ForEach(Array(store.recent.enumerated()), id: \.element.id) { index, task in
                        if index > 0 {
                            Rectangle().fill(Theme.hairlineColor)
                                .frame(height: Theme.hairline)
                                .padding(.leading, 56)   // 썸네일 폭만큼 들여쓴 헤어라인
                        }
                        MiniRow(task: task)
                    }
                }
            }
        }
    }

    // MARK: - 푸터

    private var footer: some View {
        HStack(spacing: Theme.s3) {
            Button { openMainWindow() } label: {
                Image(systemName: "square.grid.2x2")
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
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
        .font(.system(size: 12))
        .padding(.horizontal, Theme.s4)
        .padding(.vertical, 9)
    }

    private var destinationName: String {
        "→ " + (settings.outputDirectory.lastPathComponent)
    }

    // MARK: - 동작

    private var currentInputURL: String? {
        let text = urlText.isEmpty ? (clipboard.detectedURL ?? "") : urlText
        return ClipboardMonitor.extractMediaURL(from: text)
    }
    private var inputURL: String? { ClipboardMonitor.extractMediaURL(from: urlText) }

    private func add(url raw: String) {
        guard let url = ClipboardMonitor.extractMediaURL(from: raw) else { return }
        store.add(url: url, preset: preset)
        clipboard.markHandled(url)
        urlText = ""
        fieldFocused = false
        justAdded = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            justAdded = false
        }
    }

    private func openMainWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: "main")
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
            Text("대기")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
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
