import SwiftUI

/// 통계 화면 — 완료된 다운로드 기준의 요약.
/// 카드 2줄: 총계/이번달/총 용량 · 사이트 상위 · 프리셋 분포.
struct StatisticsView: View {
    @Environment(QueueStore.self) private var store

    private var stats: DownloadStats { store.stats }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.s4) {
                summaryCards
                hostSection
                presetSection
                tipSection
            }
            .padding(Theme.s4)
        }
    }

    // MARK: - 요약 카드

    private var summaryCards: some View {
        HStack(spacing: Theme.s3) {
            StatCard(symbol: "checkmark.circle.fill", tint: .green,
                     value: "\(stats.completedCount)", label: "완료 항목")
            StatCard(symbol: "calendar", tint: Theme.accent,
                     value: "\(stats.thisMonthCount)", label: "이번 달")
            StatCard(symbol: "externaldrive.fill", tint: .orange,
                     value: Fmt.bytes(stats.totalBytes), label: "총 용량")
        }
    }

    // MARK: - 사이트 상위

    @ViewBuilder private var hostSection: some View {
        let hosts = stats.topHosts(5)
        VStack(alignment: .leading, spacing: Theme.s2) {
            SectionLabel(text: "사이트별")
            if hosts.isEmpty {
                Text("완료된 항목이 없어요")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            } else {
                VStack(spacing: Theme.s1) {
                    ForEach(hosts, id: \.host) { host, count in
                        hostBar(host: host, count: count, max: hosts.first?.count ?? 1)
                    }
                }
            }
        }
        .padding(Theme.s3)
        .background(Theme.rowFill, in: RoundedRectangle(cornerRadius: Theme.rRow, style: .continuous))
    }

    private func hostBar(host: String, count: Int, max: Int) -> some View {
        HStack(spacing: Theme.s3) {
            Image(systemName: "globe")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(width: 14)
            Text(host)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1).truncationMode(.middle)
                .frame(minWidth: 120, alignment: .leading)
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Theme.accent.opacity(0.25))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Theme.accent)
                            .frame(width: geo.size.width * CGFloat(max > 0 ? Double(count) / Double(max) : 0))
                    }
            }
            .frame(height: 8)
            Text("\(count)")
                .font(.system(size: 11)).monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
        }
        .accessibilityLabel("\(host), \(count)개")
    }

    // MARK: - 프리셋 분포

    @ViewBuilder private var presetSection: some View {
        let presets = stats.topPresets()
        VStack(alignment: .leading, spacing: Theme.s2) {
            SectionLabel(text: "프리셋별")
            if presets.isEmpty {
                Text("완료된 항목이 없어요")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            } else {
                HStack(spacing: Theme.s2) {
                    ForEach(presets, id: \.preset) { preset, count in
                        Chip(symbol: preset.symbol, text: "\(preset.shortTitle) \(count)")
                    }
                }
            }
        }
        .padding(Theme.s3)
        .background(Theme.rowFill, in: RoundedRectangle(cornerRadius: Theme.rRow, style: .continuous))
    }

    // MARK: - 안내

    private var tipSection: some View {
        Label("통계는 완료된 항목을 기준으로 합니다. 목록에서 제거해도 파일은 유지됩니다.",
              systemImage: "info.circle")
            .font(.system(size: 10.5))
            .foregroundStyle(.tertiary)
    }
}

// MARK: - 카드

private struct StatCard: View {
    let symbol: String
    let tint: Color
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s1) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.s3)
        .background(Theme.rowFill, in: RoundedRectangle(cornerRadius: Theme.rRow, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.rRow, style: .continuous)
                .strokeBorder(Theme.rowBorder, lineWidth: Theme.hairline)
        )
    }
}

private struct Chip: View {
    let symbol: String
    let text: String
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 9))
            Text(text).font(.system(size: 10.5))
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Theme.accent.opacity(0.12), in: Capsule())
        .foregroundStyle(Theme.accent)
    }
}
