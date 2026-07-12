import SwiftUI

/// 화면 B — 메인 윈도우. 사이드바(필터 + 통계) + 큐 리스트 + 하단 상태바.
///
/// 분기:
/// - 필터별로 다른 빈 상태 문구/아이콘 (전부 다르게)
/// - 완료 필터에서만 "완료 지우기" 노출
/// - 통계 필터는 리스트 대신 StatisticsView 표시
/// - 드롭은 리스트가 비어 있어도 동작 (영역 전체) — .txt 파일은 줄 단위로 URL 추출
struct MainWindowView: View {
    @Environment(QueueStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filter: QueueFilter = .inProgress
    @State private var urlText = ""
    @State private var preset: Preset = .bestMP4
    @State private var playlistMode: PlaylistMode = .single
    @State private var expanding = false
    @State private var dropTargeted = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationTitle("Reel")
    }

    // MARK: - 사이드바

    private var sidebar: some View {
        List(selection: $filter) {
            Section("다운로드") {
                sidebarRow(.inProgress)
                sidebarRow(.queued)
                sidebarRow(.completed)
                sidebarRow(.failed)
            }
            Section("라이브러리") {
                sidebarRow(.all)
                sidebarRow(.audio)
                sidebarRow(.stats)
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
    }

    private func sidebarRow(_ f: QueueFilter) -> some View {
        Label {
            HStack {
                Text(f.title)
                Spacer()
                let n = store.count(f)
                if n > 0 {
                    Text("\(n)")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: f.symbol)
        }
        .tag(f)
    }

    // MARK: - 디테일

    private var detail: some View {
        VStack(spacing: 0) {
            toolbar
            Rectangle().fill(Theme.hairlineColor).frame(height: Theme.hairline)
            content
            Rectangle().fill(Theme.hairlineColor).frame(height: Theme.hairline)
            statusBar
        }
        .dropDestination(for: URL.self) { urls, _ in
            handleDrop(urls)
        } isTargeted: { dropTargeted = $0 }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: Theme.rRow, style: .continuous)
                    .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .background(Theme.accent.opacity(0.04),
                                in: RoundedRectangle(cornerRadius: Theme.rRow, style: .continuous))
                    .padding(Theme.s2)
                    .allowsHitTesting(false)
            }
        }
        .animation(Theme.motion(reduceMotion), value: dropTargeted)
    }

    // MARK: - 툴바

    private var toolbar: some View {
        HStack(spacing: Theme.s3) {
            HStack(spacing: Theme.s2) {
                Image(systemName: "plus")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("링크 붙여넣기 (여러 개 가능) 또는 이 창에 드래그", text: $urlText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .onSubmit(addFromField)
            }
            .padding(.horizontal, Theme.s3)
            .padding(.vertical, 8)
            .background(Theme.fieldFill, in: RoundedRectangle(cornerRadius: Theme.rField, style: .continuous))

            // 프리셋 + 플레이리스트 모드
            Picker("프리셋", selection: $preset) {
                ForEach(Preset.allCases) { p in Text(p.shortTitle).tag(p) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .fixedSize()

            Picker("플레이리스트", selection: $playlistMode) {
                ForEach(PlaylistMode.allCases) { m in Text(m.shortTitle).tag(m) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .fixedSize()
            .help(playlistMode == .all ? "전체 플레이리스트" : "이 영상만")

            if expanding {
                ProgressView().controlSize(.small)
            } else if !detectedURLs.isEmpty {
                Button("추가 (\(detectedURLs.count))", action: addFromField)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .controlSize(.small)
                    .transition(.opacity)
            }
            if filter == .completed && store.count(.completed) > 0 {
                Button("완료 지우기") { store.clearCompleted() }
                    .controlSize(.small)
                    .help("완료된 항목을 목록에서 제거합니다 (파일은 유지)")
            }
        }
        .padding(Theme.s3)
        .animation(Theme.motion(reduceMotion), value: !detectedURLs.isEmpty)
        .animation(Theme.motion(reduceMotion), value: expanding)
    }

    // MARK: - 콘텐츠 (필터별 빈 상태 분기 / 통계)

    @ViewBuilder private var content: some View {
        if filter == .stats {
            StatisticsView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let items = store.filtered(filter)
            if items.isEmpty {
                emptyState(for: filter)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: Theme.s2 - 2) {
                        ForEach(items) { task in
                            DownloadRowView(task: task)
                        }
                    }
                    .padding(Theme.s3)
                }
            }
        }
    }

    /// 필터마다 문구를 다르게 — 같은 빈 화면이라도 이유가 다르다.
    @ViewBuilder private func emptyState(for f: QueueFilter) -> some View {
        let (symbol, title, message): (String, String, String) = {
            switch f {
            case .inProgress:
                ("arrow.down.circle.dotted", "진행 중인 다운로드 없음",
                 "링크를 붙여넣거나 이 창으로 드래그하면 시작됩니다.")
            case .queued:
                ("clock", "대기 중인 항목 없음",
                 "동시 다운로드 한도를 넘으면 여기서 차례를 기다립니다.")
            case .completed:
                ("checkmark.circle", "아직 완료된 항목 없음",
                 "완료된 다운로드가 여기에 쌓입니다.")
            case .failed:
                ("exclamationmark.triangle", "실패한 항목 없음",
                 "좋은 소식이네요. 실패하면 여기서 다시 시도할 수 있습니다.")
            case .all:
                ("square.grid.2x2", "라이브러리가 비어 있어요",
                 "첫 링크를 붙여넣어 시작해 보세요.")
            case .audio:
                ("music.note", "오디오 항목 없음",
                 "MP3·M4A 프리셋으로 받은 항목이 여기에 모입니다.")
            case .stats:
                ("chart.bar.xaxis", "통계", "")
            }
        }()
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        }
    }

    // MARK: - 하단 상태바

    private var statusBar: some View {
        HStack(spacing: Theme.s3) {
            if store.activeCount > 0 {
                HStack(spacing: Theme.s1) {
                    StateDot(state: .downloading)
                    Text("\(store.activeCount) 진행 중")
                    if store.overallProgress > 0 {
                        Text("· \(Int(store.overallProgress * 100))%")
                    }
                }
            }
            if store.queuedCount > 0 {
                Text("\(store.queuedCount) 대기")
            }
            if store.completedToday > 0 {
                Text("오늘 \(store.completedToday)개 완료")
            }
            if store.activeCount == 0 && store.queuedCount == 0 && store.completedToday == 0 {
                Text("대기 중")
            }
            Spacer()
            Text("동시 \(store.settings.effectiveConcurrency)개")
                .help(store.settings.lowPowerProfile
                      ? "저전력 프로필이 켜져 있어 동시성이 제한됩니다"
                      : "설정에서 동시 다운로드 수를 조절할 수 있습니다")
        }
        .font(.system(size: 11)).monospacedDigit()
        .foregroundStyle(.secondary)
        .padding(.horizontal, Theme.s3)
        .padding(.vertical, 6)
    }

    // MARK: - 동작

    /// 입력 필드에서 감지된 URL 목록.
    private var detectedURLs: [String] {
        ClipboardMonitor.extractMediaURLs(from: urlText)
    }

    private func addFromField() {
        let urls = detectedURLs
        guard !urls.isEmpty else { return }
        if playlistMode == .all {
            expanding = true
            Task { @MainActor in
                store.add(url: urls.first!, preset: preset, playlistMode: .all)
                if urls.count > 1 {
                    store.addMany(urls: Array(urls.dropFirst()), preset: preset, playlistMode: .single)
                }
                expanding = false
            }
        } else {
            store.addMany(urls: urls, preset: preset, playlistMode: .single)
        }
        urlText = ""
    }

    /// 드롭 — http URL 직접 드래그 또는 .txt 파일(줄 단위 URL) 처리.
    private func handleDrop(_ urls: [URL]) -> Bool {
        var added = false
        var mediaURLs: [String] = []
        for url in urls {
            if url.isFileURL, url.pathExtension.lowercased() == "txt" {
                if let text = try? String(contentsOf: url, encoding: .utf8) {
                    mediaURLs.append(contentsOf: ClipboardMonitor.extractMediaURLs(from: text))
                }
            } else if let media = ClipboardMonitor.extractMediaURL(from: url.absoluteString) {
                mediaURLs.append(media)
            }
        }
        if !mediaURLs.isEmpty {
            store.addMany(urls: mediaURLs, preset: preset, playlistMode: playlistMode)
            added = true
        }
        return added
    }
}
