import SwiftUI
import AppKit

@main
struct ReelApp: App {
    @State private var settings: AppSettings
    @State private var store: QueueStore
    @State private var clipboard = ClipboardMonitor()

    init() {
        let settings = AppSettings()
        _settings = State(initialValue: settings)
        _store = State(initialValue: QueueStore(settings: settings))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(store)
                .environment(settings)
                .environment(clipboard)
                .frame(width: 380)
                .task { clipboard.start() }
        } label: {
            Image(systemName: store.activeCount > 0 ? "arrow.down.circle.fill" : "arrow.down.circle")
        }
        .menuBarExtraStyle(.window)

        WindowGroup(id: "main") {
            MainWindowView()
                .environment(store)
                .environment(settings)
                .frame(minWidth: 720, minHeight: 440)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 940, height: 580)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("Reel 정보…") {
                    NSApp.orderFrontStandardAboutPanel(nil)
                }
                .keyboardShortcut("i", modifiers: .command)
            }
            CommandGroup(replacing: .newItem) { EmptyView() }
            CommandGroup(replacing: .saveItem) { EmptyView() }
            CommandGroup(replacing: .printItem) { EmptyView() }

            CommandMenu("다운로드") {
                Button("붙여넣어 바로 다운로드") { pasteAndDownload() }
                    .keyboardShortcut("v", modifiers: .command)
                Button("메인 윈도우 열기") {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    NSApp.windows.first { $0.isVisible }?.makeKeyAndOrderFront(nil)
                }
                .keyboardShortcut("0", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environment(store)
                .environment(settings)
        }
    }

    /// ⌘V 처리: 텍스트 입력 중이면 일반 붙여넣기로 양보, 아니면 클립보드 URL을 바로 다운로드.
    private func pasteAndDownload() {
        if let responder = NSApp.keyWindow?.firstResponder, responder is NSTextView {
            NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
            return
        }
        if store.addFromPasteboard() != nil {
            NSApplication.shared.activate(ignoringOtherApps: true)
        } else {
            NSSound.beep()   // 클립보드에 유효한 링크가 없음
        }
    }
}
