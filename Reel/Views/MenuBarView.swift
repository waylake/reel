import SwiftUI

/// 화면 A — 메뉴바 팝오버.
///
/// 단순한 구성:
/// 1. 링크 입력창 (최상단) + 작은 컨트롤 행(프리셋·플레이리스트)
/// 2. (있을 때만) 클립보드 감지 배너 / yt-dlp 미설치 배너
/// 3. 큐 리스트 — 전체 항목 스크롤, 호버 시 빠른 동작
/// 4. 푸터 — 전체 보기 · 설정 · 종료
struct MenuBarView: View {
    @Environment(QueueStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(ClipboardMonitor.self) private var clipboard
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var urlText = ""
    @State private var preset: Preset = .bestMP4
    @State private var playlistMode: PlaylistMode = .single
    @State private var justAdded = false
    @State private var addedCount = 0
    @State private var expanding = false
    @FocusState private var fieldFocused: Bool

    private var engineMissing: Bool { BinaryResolver.ytdlp == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            inputSection
            Rectangle().fill(Theme.hairlineColor).frame(height: Theme.hairline)

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
        .onAppear {
            preset = settings.defaultPreset
            playlistMode = settings.defaultPlaylistMode
        }
    }

    // MARK: - 입력

    private var inputSection: some View {
        VStack(spacing: Theme.s2) {
            HStack(spacing: Theme.s2) {
                Image(systemName: "link")
                    .font(.system(size: 11))
                    .foregroundStyle(fieldFocused ? Theme.accent : .secondary)
                TextField("링크 붙여넣기", text: $urlText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .focused($fieldFocused)
                    .onSubmit { addFromInput() }
                if !urlText.isEmpty {
                    Button { urlText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.s3)
            .padding(.vertical, 9)
            .background(Theme.fieldFill, in: RoundedRectangle(cornerRadius: Theme.rField, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.rField, style: .continuous)
                    .strokeBorder(fieldFocused ? Theme.accent.opacity(0.5) : Color.clear, lineWidth: 1)
            )
            .animation(Theme.motion(reduceMotion), value: fieldFocused)

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

                Picker("플레이리스트", selection: $playlistMode) {
                    ForEach(PlaylistMode.allCases) { m in
                        Label(m.shortTitle, systemImage: m.symbol).tag(m)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .fixedSize()
                .help(playlistMode == .all
                      ? "전체 플레이리스트를 항목별로 받습니다"
                      : "이 영상 1개만 받습니다")

                Spacer()

                if expanding {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        addFromInput()
                    } label: {
                        Label(justAdded ? "\(addedCount)개 추가됨" : "추가",
                              systemImage: justAdded ? "checkmark" : "arrow.down")
                            .frame(minWidth: 64)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(justAdded ? .green : Theme.accent)
                    .controlSize(.small)
                    .disabled(!canAdd)
                    .keyboardShortcut(.defaultAction)
                    .animation(Theme.motion(reduceMotion), value: justAdded)
                }
            }
        }
        .padding(Theme.s3)
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

    // MARK: - 큐 리스트

    @ViewBuilder private var queueList: some View {
        if store.tasks.isEmpty {
            VStack(spacing: Theme.s1) {
                Text("받은 항목이 여기에 표시됩니다")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.s4)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(store.tasks.enumerated()), id: \.element.id) { index, task in
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
            Button { openMainWindow() } label: {
                Label("전체 보기", systemImage: "square.grid.2x2")
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

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

    /// 입력 문자열에서 감지된 URL 목록 (여러 개 가능).
    private var detectedURLs: [String] {
        ClipboardMonitor.extractMediaURLs(from: urlText)
    }

    private var canAdd: Bool { !detectedURLs.isEmpty }

    private func addFromInput() {
        let urls = detectedURLs
        guard !urls.isEmpty else { return }
        add(urls: urls)
    }

    /// 단일 링크 추가 (클립보드 배너).
    private func add(url raw: String) {
        guard let url = ClipboardMonitor.extractMediaURL(from: raw) else { return }
        add(urls: [url])
    }

    /// 여러 링크 추가 — 플레이리스트 모드면 첫 링크만 확장, 나머지는 단일 추가.
    private func add(urls: [String]) {
        clipboard.markHandled(urls.first ?? "")
        if playlistMode == .all, let first = urls.first {
            expanding = true
            Task { @MainActor in
                store.add(url: first, preset: preset, playlistMode: .all)
                if urls.count > 1 {
                    store.addMany(urls: Array(urls.dropFirst()), preset: preset, playlistMode: .single)
                }
                expanding = false
                addedCount = urls.count
                flashAdded()
            }
        } else {
            let n = store.addMany(urls: urls, preset: preset, playlistMode: .single)
            addedCount = n
            flashAdded()
        }
        urlText = ""
        fieldFocused = false
    }

    private func flashAdded() {
        justAdded = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            justAdded = false
        }
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
