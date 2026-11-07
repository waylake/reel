import SwiftUI

/// 화면 B — 메인 윈도우. 항목 카드 그리드가 전부다.
///
/// 입력창 없이 클립보드로 동작한다:
/// - 창 어디를 누르면 클립보드 링크가 큐에 추가된다 (⌘V와 동일)
/// - 링크를 창으로 드래그해도 추가된다
/// - 툴바: (완료 항목이 있을 때) 완료 지우기
///
/// 배경은 항목 유무와 관계없이 항상 창 뒤가 비치는 반투명(VisualEffectBackground)이다.
/// 카드 그리드는 ScrollView라 자체 배경이 없다 (List는 불투명 배경을 그려 빈 화면과 색이 달랐다).
struct MainWindowView: View {
    @Environment(QueueStore.self) private var store
    @State private var dropTargeted = false

    var body: some View {
        content
            .frame(minWidth: 720, maxWidth: .infinity, minHeight: 440, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { pasteFromClipboard() }
            .toolbar { toolbarContent }
            .background(VisualEffectBackground().ignoresSafeArea())
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
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: Theme.s3)],
                          spacing: Theme.s3) {
                    ForEach(store.tasks) { task in
                        DownloadCardView(task: task)
                    }
                }
                .padding(Theme.s4)
            }
        }
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
