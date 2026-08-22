import SwiftUI

/// 채널·플레이리스트 미리보기 — 2026 Liquid Glass 감성의 떠다니는 카드.
///
/// 큰 채널(수백 영상)을 받을 때 "N개 영상"을 실제로 보여주는 게 핵심이다.
/// 예전 `--dump-single-json`이 잘려 3개로 나온 문제를 `--print`로 잡고,
/// 그 개수를 다운로드 전에 보여줘 실수로 전체를 받는 걸 막는다.
struct ChannelPreview: View {
    let url: String
    /// 채널 핸들 표시용 (URL에서 뽑은 것)
    let handleLabel: String
    @Environment(QueueStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Info {
        var name: String?
        var count: Int
    }

    @State private var info: Info?
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s2) {
            header
            if !loading, let info, info.count > 0 {
                actionRow(info)
            } else if !loading {
                Text("영상을 찾지 못했어요. 링크를 확인해 보세요.")
                    .font(Theme.rowMeta)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Theme.s3)
        .background(
            RoundedRectangle(cornerRadius: Theme.rRow, style: .continuous)
                .fill(Theme.accent.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.rRow, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.22), lineWidth: Theme.hairline)
        )
        .task(id: url) { await load() }
    }

    // MARK: - 헤더 (아이콘 + 이름 + 개수)

    @ViewBuilder private var header: some View {
        HStack(spacing: Theme.s2) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 30)
            if loading {
                HStack(spacing: Theme.s2) {
                    ProgressView().controlSize(.small)
                    Text("채널 정보 불러오는 중…")
                        .font(Theme.rowMeta)
                        .foregroundStyle(.secondary)
                }
            } else if let info {
                VStack(alignment: .leading, spacing: 1) {
                    Text(info.name ?? handleLabel)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Text("\(info.count)개 영상")
                        .font(Theme.rowMeta).monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: Theme.s2)
        }
    }

    // MARK: - 액션 (전체 다운로드 + 대량 경고)

    @ViewBuilder private func actionRow(_ info: Info) -> some View {
        HStack(spacing: Theme.s2) {
            Button {
                store.add(url: url, playlistMode: .all)
            } label: {
                Label("전체 다운로드 (\(info.count)개)", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .controlSize(.small)

            if info.count > 100 {
                Label("\(info.count)개면 오래 걸려요", systemImage: "clock")
                    .font(Theme.rowMeta)
                    .foregroundStyle(.orange)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - 로딩

    private func load() async {
        loading = true
        info = nil
        let fetched = await store.fetchPlaylistInfo(url: url)
        if let fetched {
            info = Info(name: fetched.channelName, count: fetched.count ?? fetched.entries.count)
        } else {
            info = Info(name: nil, count: 0)
        }
        loading = false
    }
}
