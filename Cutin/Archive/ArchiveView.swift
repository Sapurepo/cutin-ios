/* 기록 보관 탭 — 명세 §4.2-5 / §7.4.
 *
 * 0.1.0은 로컬 `archive.json`에 id 집합을 두고 피드 배열을 걸러 만들었다. 이제 보관은 서버
 * 상태다(`GET /users/me/bookmarks`) — **걸러 만들 수 없다.** 피드에 없는(친구가 아닌 사람의,
 * 혹은 오래된) 포스트도 보관돼 있을 수 있고, 커서 키가 "보관한 시각"이라 정렬도 다르다. */

import SwiftUI

struct ArchiveView: View {
    @Environment(PostStore.self) private var store
    @Environment(\.palette) private var palette

    var body: some View {
        PostList(
            list: store.bookmarks,
            posts: store.bookmarks.ids.compactMap(store.post(id:)),
            empty: EmptyStateView(
                title: "보관한 컷이 없어요",
                message: "포스트를 열어 보관을 누르면 여기 모여요",
                systemImage: "bookmark"
            ),
            loadMore: { await store.loadBookmarks() },
            refresh: { await store.loadBookmarks(refresh: true) }
        )
        .background(palette.bg)
        .navigationTitle(AppTab.archive.title)
        .routeDestinations()
        /* 탭에 들어올 때마다 확인한다. 보관은 상세 화면에서 바뀌므로, 한 번만 받으면
         * 방금 보관한 포스트가 여기 없다(`toggleBookmark`가 `hasLoaded`를 내려 둔다). */
        .task { await store.loadBookmarks() }
    }
}
