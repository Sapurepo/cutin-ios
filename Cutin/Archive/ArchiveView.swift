/* 기록 보관 탭 — 명세 §4.2-5 / §7.4.
 *
 * 보관 목록을 따로 저장하지 않는다. `ArchiveStore`는 id 집합만 들고, 목록은 피드와 같은
 * 포스트 배열을 걸러 만든다 — 순서·캡션·보정이 두 곳에서 갈라질 수 없다. */

import SwiftUI

struct ArchiveView: View {
    @Environment(FeedStore.self) private var store
    @Environment(ArchiveStore.self) private var archive
    @Environment(\.palette) private var palette

    private var archived: [ComposedPost] {
        store.posts.filter { archive.contains($0.id) }
    }

    var body: some View {
        Group {
            if archived.isEmpty {
                EmptyStateView(
                    title: "보관한 컷이 없어요",
                    message: "포스트를 열어 보관을 누르면 여기 모여요",
                    systemImage: "bookmark"
                )
            } else {
                list
            }
        }
        .background(palette.bg)
        .navigationTitle(AppTab.archive.title)
        .navigationDestination(for: Route.self) { route in
            switch route {
            case .postDetail(let id):
                PostDetailView(id: id)
            }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.x6) {
                ForEach(archived) { post in
                    NavigationLink(value: Route.postDetail(post.id)) {
                        PostCard(post: post)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.x4)
            .padding(.vertical, Spacing.x4)
        }
    }
}
