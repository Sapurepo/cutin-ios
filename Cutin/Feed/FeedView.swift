/* 피드 — 명세 §4.1.
 *
 * 상세는 시트가 아니라 **푸시**다. 시트는 "여기서 잠깐 보고 돌아온다"는 뜻인데, 상세에는
 * 삭제·보관처럼 목록을 바꾸는 동작이 있어 되돌아온 목록이 달라져 있다.
 *
 * 0.1.0은 로컬 인덱스가 통째로 메모리에 있어 무한 스크롤이 필요 없었다. 이제 서버 목록이라
 * **커서 페이징**이 실제로 필요하다 — 마지막 카드가 보이면 다음 페이지를 받는다. */

import SwiftUI

struct FeedView: View {
    @Environment(PostStore.self) private var store
    @Environment(\.palette) private var palette

    var body: some View {
        PostList(
            list: store.feed,
            posts: store.feed.ids.compactMap(store.post(id:)),
            empty: EmptyStateView(
                title: "아직 남긴 컷이 없어요",
                message: "가운데 촬영 버튼으로 첫 컷을 찍어보세요",
                systemImage: AppTab.home.systemImage
            ),
            loadMore: { await store.loadFeed() },
            refresh: { await store.loadFeed(refresh: true) }
        )
        .background(palette.bg)
        .navigationTitle("CUTIN")
        .routeDestinations()
        .task { await store.loadFeed() }
    }
}

/* 피드와 보관 탭이 같은 목록이다 — 데이터 출처와 빈 상태 문구만 다르다.
 * 두 번 쓰기 때문에 뽑았다(호출부 2곳 규칙). */
struct PostList<Empty: View>: View {
    let list: PostStore.List
    let posts: [Post]
    let empty: Empty
    let loadMore: @Sendable () async -> Void
    let refresh: @Sendable () async -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        Group {
            if !posts.isEmpty {
                content
            } else if list.isLoading || !list.hasLoaded {
                ProgressView()
                    .tint(palette.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let failure = list.failure {
                /* 실패와 빈 목록을 가른다. 실패했는데 "아직 남긴 컷이 없어요"를 보여주면
                 * 사용자는 자기 포스트가 사라진 줄 안다. */
                EmptyStateView(title: "불러오지 못했어요", message: failure,
                               systemImage: "exclamationmark.triangle") {
                    Button("다시 시도") { Task { await refresh() } }
                        .primaryGlassButton(tint: palette.accent)
                }
            } else {
                empty
            }
        }
        .refreshable { await refresh() }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.x6) {
                ForEach(posts, id: \.id) { post in
                    NavigationLink(value: Route.postDetail(post.id)) {
                        PostCard(post: post)
                    }
                    .buttonStyle(.plain)
                }

                /* 다음 페이지 신호. 마지막 카드가 화면에 들어오면 `.task`가 돌아 더 받는다 —
                 * 스크롤 오프셋을 재는 것보다 짧고, 화면 크기·카드 높이에 기대지 않는다. */
                if list.nextCursor != nil {
                    ProgressView()
                        .tint(palette.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.x4)
                        .task { await loadMore() }
                }
            }
            .padding(.horizontal, Spacing.x4)
            .padding(.vertical, Spacing.x4)
        }
    }
}
