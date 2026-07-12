import SwiftUI

/// 설정 — 기본값과 부가 옵션. 변경 즉시 UserDefaults에 영속화.
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(QueueStore.self) private var store

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("일반", systemImage: "gearshape") }
            formatTab
                .tabItem { Label("포맷", systemImage: "slider.horizontal.3") }
            engineTab
                .tabItem { Label("엔진", systemImage: "wrench.and.screwdriver") }
            SupportedSitesView()
                .tabItem { Label("지원 사이트", systemImage: "globe") }
        }
        .frame(width: 520, height: 500)
    }

    // MARK: - 일반

    private var generalTab: some View {
        Form {
            Section("기본 동작") {
                Picker("기본 프리셋", selection: bind(\.defaultPreset)) {
                    ForEach(Preset.allCases) { p in Text(p.title).tag(p) }
                }
                Picker("플레이리스트 기본 모드", selection: bind(\.defaultPlaylistMode)) {
                    ForEach(PlaylistMode.allCases) { m in Text(m.title).tag(m) }
                }
                Stepper(value: bind(\.maxPlaylistItems), in: 1...200) {
                    LabeledContent("전체 받기 최대 항목", value: "\(settings.maxPlaylistItems)개")
                }
                .disabled(settings.defaultPlaylistMode == .single)
            }
            Section("동시성") {
                Stepper(value: bind(\.maxConcurrent), in: 1...6) {
                    LabeledContent("동시 다운로드", value: "\(settings.maxConcurrent)개")
                }
                Toggle("클립보드 링크 자동 감지", isOn: bind(\.autoDetectClipboard))
                Toggle("완료 시 알림", isOn: bind(\.notifyOnComplete))
                Toggle("저전력 프로필 (동시성↓ · 속도 8M 제한)", isOn: bind(\.lowPowerProfile))
            }
            Section {
                Toggle("완료 항목 자동 정리", isOn: bind(\.autoClearCompleted))
                Stepper(value: bind(\.autoClearAfterDays), in: 1...90) {
                    LabeledContent("보관 기간", value: "\(settings.autoClearAfterDays)일")
                }
                .disabled(!settings.autoClearCompleted)
            } header: {
                Text("완료 항목")
            } footer: {
                Text(settings.autoClearCompleted
                     ? "앱 시작 시 \(settings.autoClearAfterDays)일이 지난 완료 항목을 목록에서 제거합니다. 파일은 유지됩니다."
                     : "완료된 항목이 목록에 계속 쌓입니다. 자동 정리를 켜면 기간이 지난 항목을 시작 시 제거합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("저장 위치") {
                LabeledContent("폴더") {
                    HStack {
                        Text(settings.outputDirectoryPath)
                            .lineLimit(1).truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("변경…", action: chooseFolder).controlSize(.small)
                    }
                }
            }
            Section {
                Toggle("파일명에 영상 ID 포함", isOn: bind(\.includeVideoID))
            } header: {
                Text("파일명")
            } footer: {
                // 라이브 미리보기 — 토글에 따라 실제 결과 예시가 바뀐다
                Text(settings.includeVideoID
                     ? "예: 영상 제목 [dQw4w9WgXcQ].mp4 — 같은 제목이 겹쳐도 안전해요."
                     : "예: 영상 제목.mp4 — 제목이 같은 영상을 받으면 덮어쓸 수 있어요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 포맷

    private var formatTab: some View {
        Form {
            Section("자막") {
                Toggle("자막 임베드", isOn: bind(\.embedSubtitles))
                TextField("자막 언어 (쉼표 구분)", text: bind(\.subtitleLangsText))
                    .disabled(!settings.embedSubtitles)
                Toggle("자동 생성 자막 포함", isOn: bind(\.autoSubtitles))
                    .disabled(!settings.embedSubtitles)
            }
            Section("메타데이터") {
                Toggle("챕터 임베드", isOn: bind(\.embedChapters))
                Toggle("메타데이터 임베드", isOn: bind(\.embedMetadata))
                Toggle("썸네일 임베드", isOn: bind(\.embedThumbnail))
            }
            Section("파워 옵션") {
                Toggle("SponsorBlock 구간 제거", isOn: bind(\.sponsorBlock))
                Picker("로그인 쿠키", selection: bind(\.cookiesFromBrowser)) {
                    Text("사용 안 함").tag("")
                    Text("Safari").tag("safari")
                    Text("Chrome").tag("chrome")
                    Text("Firefox").tag("firefox")
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 엔진

    @State private var ytdlpVersion: String?
    @State private var updating = false
    @State private var updateMessage: String?
    @State private var updateOk = false

    private var engineTab: some View {
        Form {
            Section {
                LabeledContent("yt-dlp 버전") {
                    HStack(spacing: Theme.s2) {
                        if let v = ytdlpVersion {
                            Text(v).font(.system(.body, design: .monospaced))
                        } else if BinaryResolver.ytdlp == nil {
                            Text("설치되지 않음").foregroundStyle(.red)
                        } else {
                            ProgressView().controlSize(.small)
                        }
                        Button("새로고침") { refreshVersion() }
                            .controlSize(.small)
                            .disabled(BinaryResolver.ytdlp == nil)
                    }
                }
                if BinaryResolver.ytdlp != nil {
                    Button {
                        runUpdate()
                    } label: {
                        if updating {
                            HStack { ProgressView().controlSize(.small); Text("업데이트 중…") }
                        } else {
                            Text("yt-dlp 업데이트")
                        }
                    }
                    .disabled(updating || BinaryResolver.isBundled)
                    .help(BinaryResolver.isBundled
                          ? "번들 포함 바이너리는 자체 업데이트 불가 — 앱 업데이트 필요"
                          : "yt-dlp -U 로 자체 업데이트")
                    if let msg = updateMessage {
                        Label(msg, systemImage: updateOk ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(updateOk ? .green : .orange)
                            .lineLimit(3)
                    }
                    if BinaryResolver.isBundled {
                        Text("앱 번들에 포함된 yt-dlp는 자체 업데이트할 수 없어요. Reel 앱을 업데이트해 주세요.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("yt-dlp")
            } footer: {
                Text("yt-dlp는 사이트 추출기를 자주 업데이트합니다. 다운로드가 갑자기 안 되면 먼저 업데이트를 시도해 보세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("ffmpeg") {
                    if BinaryResolver.ffmpeg != nil {
                        Label("감지됨", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.body)
                    } else {
                        Label("미감지", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.body)
                    }
                }
            } header: {
                Text("ffmpeg")
            } footer: {
                Text("영상 병합·변환·오디오 추출에 필요합니다. brew install ffmpeg 로 설치하세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { if ytdlpVersion == nil { refreshVersion() } }
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
