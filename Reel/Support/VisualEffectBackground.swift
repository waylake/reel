import AppKit
import SwiftUI

/// 창 뒤(바탕화면·다른 창)가 비치는 반투명 배경.
/// SwiftUI `Material`은 창 내부 블렌딩이라 창 뒤가 비치지 않으므로 NSVisualEffectView를 직접 쓴다.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active   // 창이 비활성이어도 항상 반투명 유지
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
    }
}
