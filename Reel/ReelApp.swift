import SwiftUI
import AppKit

// MARK: - AppDelegate

/// GUI 윈도우를 직접 관리.
/// SwiftUI에서 MenuBarExtra가 있으면 WindowGroup이 자동으로 열리지 않으므로,
/// AppDelegate가 NSWindow + NSHostingController로 메인 윈도우를 직접 생성한다.
/// 이 방식은 시작 시 자동 열기와 메뉴바에서의 재열기를 결정론적으로 처리한다.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
    let store: QueueStore
    let clipboard = ClipboardMonitor()
    let updater = UpdaterStore()
    private var mainWindow: NSWindow?

    override init() {
        store = QueueStore(settings: settings)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 시작은 regular: Dock + Cmd+Tab에 표시.
        NSApp.setActivationPolicy(.regular)
        // 메인 GUI 윈도우를 즉시 띄운다 — 메뉴바만 나오는 문제 해결의 핵심.
        showMainWindow()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    /// 마지막 윈도우가 닫히면 accessory로 복귀 (Dock 숨김, 앱은 종료하지 않음) —
    /// 메뉴바만 남겨둔 채 대기. 메뉴바 "전체 보기"로 다시 열면 regular로 돌아온다.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        if NSApp.activationPolicy() == .regular {
            NSApp.setActivationPolicy(.accessory)
        }
        return false
    }

    /// 앱이 이미 실행 중일 때 사용자가 Dock 아이콘을 클릭하거나 앱을 다시 실행한 경우.
    /// 보이는 윈도우가 없으면(이전에 GUI 창을 닫은 상태) 메인 윈도우를 다시 띄운다.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if flag {
            // 이미 보이는 윈도우가 있으면 그대로 활성화
            NSApplication.shared.activate(ignoringOtherApps: true)
        } else {
            // 보이는 윈도우가 없으면 메인 GUI 윈도우를 다시 표시
            showMainWindow()
        }
        return true
    }

    /// 메인 GUI 윈도우 표시 — 이미 있으면 앞으로/복원, 없으면 새로 생성.
    func showMainWindow() {
        if let window = mainWindow {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            createMainWindow()
        }
        if NSApp.activationPolicy() == .accessory {
            NSApp.setActivationPolicy(.regular)
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func createMainWindow() {
        let rootView = MainWindowView()
            .environment(store)
            .environment(settings)
        let hosting = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Reel"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 940, height: 580))
        window.minSize = NSSize(width: 720, height: 440)
        window.center()
        // 닫혀도 객체 유지 — 메뉴바에서 재열기 시 같은 윈도우를 다시 보인다.
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        mainWindow = window
    }
}

// MARK: - App

@main
struct ReelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(appDelegate.store)
                .environment(appDelegate.settings)
                .environment(appDelegate.clipboard)
                .environment(appDelegate.updater)
                .frame(width: 380)
                .task { appDelegate.clipboard.start() }
        } label: {
            menubarLabel
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("Reel 정보…") {
                    NSApp.orderFrontStandardAboutPanel(nil)
                }
                .keyboardShortcut("i", modifiers: .command)
                Button("업데이트 확인…") {
                    appDelegate.updater.checkForUpdates()
                }
            }
            CommandGroup(replacing: .newItem) { EmptyView() }
            CommandGroup(replacing: .saveItem) { EmptyView() }
            CommandGroup(replacing: .printItem) { EmptyView() }

            CommandMenu("다운로드") {
                Button("붙여넣어 바로 다운로드") { pasteAndDownload() }
                    .keyboardShortcut("v", modifiers: .command)
                Button("메인 윈도우 열기") { appDelegate.showMainWindow() }
                    .keyboardShortcut("0", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environment(appDelegate.store)
                .environment(appDelegate.settings)
                .environment(appDelegate.updater)
        }
    }

    /// 메뉴바 라벨 — 활성 다운로드가 있으면 진행률을 표시한다.
    @ViewBuilder private var menubarLabel: some View {
        if appDelegate.store.activeCount > 0 {
            HStack(spacing: 3) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.teal)
                Text("\(Int(appDelegate.store.overallProgress * 100))%")
                    .monospacedDigit()
                    .font(.system(size: 12, weight: .medium))
            }
            .accessibilityLabel("Reel — \(appDelegate.store.activeCount)개 진행 중, \(Int(appDelegate.store.overallProgress * 100))퍼센트")
        } else {
            Image(systemName: "arrow.down.circle")
                .accessibilityLabel("Reel")
        }
    }

    /// ⌘V 처리: 텍스트 입력 중이면 일반 붙여넣기로 양보, 아니면 클립보드 URL을 바로 다운로드.
    private func pasteAndDownload() {
        if let responder = NSApp.keyWindow?.firstResponder, responder is NSTextView {
            NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
            return
        }
        if appDelegate.store.addFromPasteboard() != nil {
            NSApplication.shared.activate(ignoringOtherApps: true)
        } else {
            NSSound.beep()   // 클립보드에 유효한 링크가 없음
        }
    }
}
