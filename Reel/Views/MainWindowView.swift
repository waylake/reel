import SwiftUI

/// 화면 B — 메인 윈도우. 항목 한 줄 목록이 전부다.
///
/// 입력창 없이 클립보드로 동작한다:
/// - 창 어디를 누르면 클립보드 링크가 큐에 추가된다 (⌘V와 동일)
/// - 링크를 창으로 드래그해도 추가된다
/// - 툴바: 붙여넣기 · (완료 항목이 있을 때) 완료 지우기
struct MainWindowView: View {
    @Environment(QueueStore.self) private var store
    @State private var dropTargeted = false

    var body: some View {
        content
            .contentShape(Rectangle())
            .onTapGesture { pasteFromClipboard() }
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .bottom, spacing: 0) { statusBar }
            .dropDestination(for: URL.self) { urls, _ in
                handleDrop(urls)
            } isTargeted: { dropTargeted = $0 }
            .overlay {
                if dropTargeted {
                    RoundedRectangle(cornerRadius: Theme.rRow, style: .continuous)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .padding(Theme.s2)
                        .allowsHitTesting(false)
                }
            }
    }

    // MARK: - 툴바

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if store.completedCount > 0 {
                Button("완료 지우기", systemImage: "trash") { store.clearCompleted() }
                    .help("완료된 항목을 목록에서 제거합니다 (파일은 유지)")
            }
            Button("붙여넣기", systemImage: "doc.on.clipboard") { pasteFromClipboard() }
                .help("클립보드의 링크를 다운로드 목록에 추가 (⌘V)")
        }
    }

    // MARK: - 콘텐츠

    @ViewBuilder private var content: some View {
        if store.tasks.isEmpty {
            ContentUnavailableView {
                Label("받은 항목이 없어요", systemImage: "arrow.down.circle.dotted")
            } description: {
                Text("아무 곳이나 클릭하면 클립보드의 링크를 받아요.\n링크를 이 창으로 드래그해도 됩니다.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(store.tasks) { task in
                DownloadRowView(task: task)
            }
            .listStyle(.inset)
        }
    }

    // MARK: - 하단 상태 막대

    private var statusBar: some View {
        HStack(spacing: Theme.s3) {
            if store.activeCount > 0 {
                Label("\(store.activeCount)개 진행 중", systemImage: "arrow.down.circle")
                if store.overallProgress > 0 {
                    Text("\(Int(store.overallProgress * 100))%")
                }
            }
            if store.queuedCount > 0 {
                Text("대기 \(store.queuedCount)")
            }
            if store.activeCount == 0 && store.queuedCount == 0 {
                Text("대기 중")
            }
            Spacer()
            Text("동시 \(store.settings.effectiveConcurrency)개")
                .help(store.settings.lowPowerProfile
                      ? "저전력 프로필이 켜져 있어 동시성이 제한됩니다"
                      : "설정에서 동시 다운로드 수를 조절할 수 있습니다")
        }
        .font(.caption).monospacedDigit()
        .foregroundStyle(.secondary)
        .padding(.horizontal, Theme.s3)
        .padding(.vertical, Theme.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }

    // MARK: - 동작

    /// 클립보드 링크를 큐에 추가. 링크가 없으면 비프음.
    /// 프리셋·플레이리스트 모드는 설정(기본값)을 따른다.
    private func pasteFromClipboard() {
        if store.addFromPasteboard() == nil {
            NSSound.beep()
        }
    }

    /// 드롭 — http URL 직접 드래그 또는 .txt 파일(줄 단위 URL) 처리.
    private func handleDrop(_ urls: [URL]) -> Bool {
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
        guard !mediaURLs.isEmpty else { return false }
        store.addMany(urls: mediaURLs)
        return true
    }
}
