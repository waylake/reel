import SwiftUI

/// 설정 → 지원 사이트 탭.
/// 설치된 yt-dlp의 추출기 목록을 직접 조회(--list-extractors)해 항상 최신 상태로 검색.
struct SupportedSitesView: View {
    @Environment(QueueStore.self) private var store

    @State private var all: [String] = []
    @State private var query = ""
    @State private var loading = true

    private var filtered: [String] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        return all.filter { $0.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            content
            Divider()
            footer
        }
        .task {
            if all.isEmpty {
                all = await store.supportedSites()
                loading = false
            }
        }
    }

    // MARK: - 검색 바

    private var searchBar: some View {
        HStack(spacing: Theme.s2) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
            TextField("사이트 검색 — youtube, twitter, vimeo, tiktok …", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.s3)
        .padding(.vertical, Theme.s2 + 2)
    }

    // MARK: - 콘텐츠

    @ViewBuilder private var content: some View {
        if loading {
            VStack(spacing: Theme.s2) {
                ProgressView()
                Text("지원 사이트 불러오는 중…")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if all.isEmpty {
            ContentUnavailableView {
                Label("목록을 불러올 수 없어요", systemImage: "wifi.exclamationmark")
            } description: {
                Text("yt-dlp가 설치돼 있는지 확인해 주세요.")
            }
        } else if filtered.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(filtered.enumerated()), id: \.element) { index, site in
                        SiteRow(name: site, query: query)
                        if index < filtered.count - 1 {
                            Rectangle().fill(Theme.hairlineColor)
                                .frame(height: Theme.hairline)
                                .padding(.leading, Theme.s3)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - 푸터

    private var footer: some View {
        HStack {
            if !loading && !all.isEmpty {
                Text(query.isEmpty
                     ? "\(all.count)개 사이트 지원"
                     : "\(filtered.count) / \(all.count)개")
                    .monospacedDigit()
            }
            Spacer()
            Link("전체 목록 보기 ↗", destination: URL(string: "https://github.com/yt-dlp/yt-dlp/blob/master/supportedsites.md")!)
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
        .padding(.horizontal, Theme.s3)
        .padding(.vertical, Theme.s2)
    }
}

/// 사이트 한 줄 — 검색어에 걸린 부분을 강조.
private struct SiteRow: View {
    let name: String
    let query: String
    @State private var hovering = false

    var body: some View {
        HStack(spacing: Theme.s2) {
            Image(systemName: "globe")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            highlighted
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
            Spacer()
        }
        .padding(.horizontal, Theme.s3)
        .padding(.vertical, 5)
        .background(hovering ? Theme.rowFillHover : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private var highlighted: Text {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty,
              let range = name.range(of: q, options: .caseInsensitive) else {
            return Text(name)
        }
        let before = String(name[name.startIndex..<range.lowerBound])
        let match = String(name[range])
        let after = String(name[range.upperBound...])
        return Text(before)
            + Text(match).foregroundColor(Theme.accent).bold()
            + Text(after)
    }
}
