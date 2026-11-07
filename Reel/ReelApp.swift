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
    private var pasteMonitor: Any?

    override init() {
        store = QueueStore(settings: settings)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // UI 테스트 중에는 부작용(활성화·윈도우 강제 오픈)을 줄여
        // XCUITest 러너 부트스트랩과 경합하지 않게 한다. (#12)
        if ProcessInfo.processInfo.arguments.contains("UITESTING") { return }
        installPasteShortcut()
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

    // MARK: - ⌘V

    /// ⌘V → 클립보드 링크 다운로드.
    ///
    /// 메뉴의 단축키(.keyboardShortcut)로는 동작하지 않았다: 기본 "편집 > 붙여넣기"가 같은 ⌘V를
    /// 먼저 가져가는데, 메인 창에는 paste:를 받을 응답자가 없어 아무 일도 일어나지 않았다.
    /// 로컬 키 모니터는 메뉴 단축키 처리보다 먼저 호출되므로 여기서 가로챈다.
    /// - 텍스트 입력 중(설정의 자막 언어 등)이면 일반 붙여넣기로 양보
    /// - 한글 등 비라틴 입력 소스에서도 동작하도록 물리 키(V = keyCode 9)로도 판별
    private func installPasteShortcut() {
        pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isV = event.keyCode == 9 || event.charactersIgnoringModifiers?.lowercased() == "v"
            guard flags == .command, isV else { return event }
            if NSApp.keyWindow?.firstResponder is NSTextView { return event }
            self.pasteFromClipboard()
            return nil
        }
    }

    /// 클립보드 링크를 큐에 추가. 링크가 없으면 비프음.
    /// 프리셋·플레이리스트 모드는 설정(기본값)을 따른다.
    func pasteFromClipboard() {
        if let task = store.addFromPasteboard() {
            clipboard.markHandled(task.url)
        } else {
            NSSound.beep()
        }
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
        // 창 크기를 SwiftUI 이상적 크기에 맞추지 않는다 — 최소 크기만 반영.
        // 카드 그리드(ScrollView + LazyVGrid)는 이상적 폭이 0에 가까워, 기본 동작이면
        // 창이 폭 32pt로 쪼그라들었다. (v1.3.0)
        hosting.sizingOptions = [.minSize]
        let window = NSWindow(contentViewController: hosting)
        window.title = "Reel"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true   // 반투명 배경이 제목줄까지 이어지도록
        window.setContentSize(NSSize(width: 940, height: 580))
        window.minSize = NSSize(width: 720, height: 440)
        window.toolbarStyle = .unified   // 제목줄과 툴바를 하나로 — 최신 macOS 기본 형태
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
                    let creditsText = "Developed by waylake\nGitHub: https://github.com/waylake"
                    let credits = NSMutableAttributedString(
                        string: creditsText,
                        attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)]
                    )
                    let linkRange = (creditsText as NSString).range(of: "https://github.com/waylake")
                    credits.addAttribute(.link, value: "https://github.com/waylake", range: linkRange)
                    
                    NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
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

    /// 메뉴 "붙여넣어 바로 다운로드" 클릭. (⌘V 키 입력은 AppDelegate의 키 모니터가 처리)
    private func pasteAndDownload() {
        appDelegate.pasteFromClipboard()
    }
}
