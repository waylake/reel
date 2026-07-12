import SwiftUI
import Sparkle

@MainActor
@Observable
final class UpdaterStore {
    private let updaterController: SPUStandardUpdaterController

    init() {
        // 백그라운드 체크 활성화, 기본 UI 드라이버 사용
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    /// 수동으로 업데이트 확인을 트리거합니다.
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
