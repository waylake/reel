import SwiftUI

/// 설정 — 변경 즉시 UserDefaults에 영속화.
///
/// 구성 원칙: 자주 쓰는 것만 앞에, 나머지는 "고급"으로.
/// - 일반: 저장 위치 · 기본 포맷 · 알림/클립보드
/// - 다운로드: 플레이리스트 · 파일에 포함할 것 · 쿠키
/// - 고급: 성능 · 목록 정리 · 엔진(yt-dlp/ffmpeg)
/// 하위 옵션은 상위 토글이 켜졌을 때만 보이고, 긴 설명은 footer 대신 .help 툴팁으로 둔다.
/// 탭마다 높이를 고정해 탭 전환 시 창이 내용 크기에 맞춰진다 (하위 옵션이 펼쳐지면 스크롤).
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(QueueStore.self) private var store
    @Environment(UpdaterStore.self) private var updater

    var body: some View {
        TabView {
            generalTab
                .frame(height: 300)
                .tabItem { Label("일반", systemImage: "gearshape") }
            downloadTab
                .frame(height: 440)
                .tabItem { Label("다운로드", systemImage: "arrow.down.circle") }
            advancedTab
                .frame(height: 500)
                .tabItem { Label("고급", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 480)
    }

    // MARK: - 일반

    private var generalTab: some View {
        Form {
            Section {
                LabeledContent("저장 위치") {
                    Button(action: chooseFolder) {
                        Label(folderName, systemImage: "folder")
                            .lineLimit(1).truncationMode(.middle)
                    }
                    .help(settings.outputDirectoryPath)
                }
                Picker("기본 포맷", selection: bind(\.defaultPreset)) {
                    ForEach(Preset.allCases) { p in Text(p.title).tag(p) }
                }
            }
            Section {
                Toggle("복사한 링크 자동 감지", isOn: bind(\.autoDetectClipboard))
                Toggle("완료되면 알림", isOn: bind(\.notifyOnComplete))
            }
            Section {
                LabeledContent("앱 업데이트") {
                    Button("확인…") { updater.checkForUpdates() }
                }
            }
        }
        .formStyle(.grouped)
    }

    /// 경로 전체 대신 폴더 이름만 — 전체 경로는 툴팁으로.
    private var folderName: String {
        let name = (settings.outputDirectoryPath as NSString).lastPathComponent
        return name.isEmpty ? settings.outputDirectoryPath : name
    }

    // MARK: - 다운로드

    private var downloadTab: some View {
        Form {
            Section("플레이리스트") {
                Picker("링크가 목록일 때", selection: bind(\.defaultPlaylistMode)) {
                    ForEach(PlaylistMode.allCases) { m in Text(m.title).tag(m) }
                }
                if settings.defaultPlaylistMode != .single {
                    LabeledContent("최대") {
                        Stepper("\(settings.maxPlaylistItems)개", value: bind(\.maxPlaylistItems), in: 1...2000)
                    }
                    .help("일반 플레이리스트는 이 개수까지만 받습니다. 채널은 미리보기의 '전체 다운로드'를 누르면 제한 없이 받아요.")
                }
            }
            Section("파일에 포함") {
                Toggle("자막", isOn: bind(\.embedSubtitles))
                if settings.embedSubtitles {
                    TextField("언어", text: bind(\.subtitleLangsText), prompt: Text("ko,en"))
                    Toggle("자동 생성 자막도 포함", isOn: bind(\.autoSubtitles))
                }
                Toggle("썸네일 · 챕터 · 메타데이터", isOn: embedAllBinding)
                Toggle("파일명에 영상 ID", isOn: bind(\.includeVideoID))
                    .help(settings.includeVideoID
                          ? "예: 영상 제목 [dQw4w9WgXcQ].mp4 — 같은 제목이 겹쳐도 안전해요."
                          : "예: 영상 제목.mp4 — 제목이 같은 영상을 받으면 덮어쓸 수 있어요.")
                Toggle("광고 구간 제거 (SponsorBlock)", isOn: bind(\.sponsorBlock))
            }
            Section {
                Picker("로그인 쿠키", selection: bind(\.cookiesFromBrowser)) {
                    Text("사용 안 함").tag("")
                    Text("Safari").tag("safari")
                    Text("Chrome").tag("chrome")
                    Text("Firefox").tag("firefox")
                }
                .help("연령 제한·멤버십 영상처럼 로그인이 필요할 때 브라우저의 로그인 정보를 사용합니다.")
            }
        }
        .formStyle(.grouped)
    }

    /// 썸네일·챕터·메타데이터를 하나의 토글로 묶는다. 하나라도 꺼져 있으면 꺼진 것으로 표시.
    private var embedAllBinding: Binding<Bool> {
        Binding(
            get: { settings.embedThumbnail && settings.embedChapters && settings.embedMetadata },
            set: { on in
                settings.embedThumbnail = on
                settings.embedChapters = on
                settings.embedMetadata = on
                settings.persist()
            }
        )
    }

    // MARK: - 고급

    @State private var ytdlpVersion: String?
    @State private var updating = false
    @State private var updateMessage: String?
    @State private var updateOk = false
    @State private var showSites = false

    private var advancedTab: some View {
        Form {
            Section("성능") {
                LabeledContent("동시 다운로드") {
                    Stepper("\(settings.maxConcurrent)개", value: bind(\.maxConcurrent), in: 1...6)
                }
                Toggle("저전력 모드", isOn: bind(\.lowPowerProfile))
                    .help("동시 다운로드를 줄이고 속도를 8MB/s로 제한합니다.")
            }
            Section("목록 정리") {
                Toggle("완료 항목 자동 삭제", isOn: bind(\.autoClearCompleted))
                    .help("앱 시작 시 기간이 지난 완료 항목을 목록에서 지웁니다. 파일은 그대로 남아요.")
                if settings.autoClearCompleted {
                    LabeledContent("보관 기간") {
                        Stepper("\(settings.autoClearAfterDays)일", value: bind(\.autoClearAfterDays), in: 1...90)
                    }
                }
            }
            Section("엔진") {
                LabeledContent("yt-dlp") {
                    HStack(spacing: Theme.s2) {
                        ytdlpStatus
                        if BinaryResolver.ytdlp != nil {
                            Button(updating ? "업데이트 중…" : "업데이트") { runUpdate() }
                                .controlSize(.small)
                                .disabled(updating)
                                .help("다운로드가 갑자기 안 되면(403 등) 먼저 업데이트해 보세요. 재시작 없이 바로 적용돼요.")
                        }
                    }
                }
                if let msg = updateMessage {
                    Label(msg, systemImage: updateOk ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(updateOk ? .green : .orange)
                        .lineLimit(3)
                }
                LabeledContent("ffmpeg") {
                    if BinaryResolver.ffmpeg != nil {
                        Label("사용 가능", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("없음 — brew install ffmpeg", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
                Button("지원 사이트 목록…") { showSites = true }
            }
        }
        .formStyle(.grouped)
        .task { if ytdlpVersion == nil { refreshVersion() } }
        .sheet(isPresented: $showSites) {
            SupportedSitesView()
                .frame(minWidth: 480, minHeight: 420)
        }
    }

    @ViewBuilder private var ytdlpStatus: some View {
        if let v = ytdlpVersion {
            Text(v).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
        } else if BinaryResolver.ytdlp == nil {
            Text("설치되지 않음").foregroundStyle(.red)
        } else {
            ProgressView().controlSize(.small)
        }
    }

    private func refreshVersion() {
        Task { @MainActor in
            ytdlpVersion = await store.ytdlpVersion()
        }
    }

    private func runUpdate() {
        updating = true
        updateMessage = nil
        Task { @MainActor in
            let result = await store.updateYtdlp()
            updateOk = result.ok
            updateMessage = result.message
            updating = false
            refreshVersion()
        }
    }

    // MARK: - 헬퍼

    /// 값 변경 시 즉시 persist() 하는 바인딩.
    private func bind<T>(_ keyPath: ReferenceWritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { settings[keyPath: keyPath] = $0; settings.persist() }
        )
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "선택"
        if panel.runModal() == .OK, let url = panel.url {
            settings.outputDirectoryPath = url.path
            settings.persist()
        }
    }
}
