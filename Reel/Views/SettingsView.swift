import SwiftUI

/// 설정 — 기본값과 부가 옵션. 변경 즉시 UserDefaults에 영속화.
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("일반", systemImage: "gearshape") }
            formatTab
                .tabItem { Label("포맷", systemImage: "slider.horizontal.3") }
            SupportedSitesView()
                .tabItem { Label("지원 사이트", systemImage: "globe") }
        }
        .frame(width: 480, height: 460)
    }

    // MARK: - 일반

    private var generalTab: some View {
        Form {
            Section("기본 동작") {
                Picker("기본 프리셋", selection: bind(\.defaultPreset)) {
                    ForEach(Preset.allCases) { p in Text(p.title).tag(p) }
                }
                Stepper(value: bind(\.maxConcurrent), in: 1...6) {
                    LabeledContent("동시 다운로드", value: "\(settings.maxConcurrent)개")
                }
                Toggle("클립보드 링크 자동 감지", isOn: bind(\.autoDetectClipboard))
                Toggle("완료 시 알림", isOn: bind(\.notifyOnComplete))
                Toggle("저전력 프로필 (동시성↓ · 속도 8M 제한)", isOn: bind(\.lowPowerProfile))
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
