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
    @Environment(NotificationStore.self) private var notifications
    @Environment(\.palette) private var palette

    var body: some View {
        PostList(
            list: store.feed,
            posts: store.feed.ids.compactMap(store.post(id:)),
            // 빈 피드의 그림은 빈 스트립 — 로그인·팁과 같은 물건이라 "찍으면 여기 이렇게 온다"가 보인다.
            empty: EmptyStateView(
                title: "아직 남긴 컷이 없어요",
                message: "가운데 촬영 버튼으로 첫 컷을 찍어보세요"
            ) {
                StripArt(layout: .strip4, skin: .white, width: 64, filled: 0)
                    .rotationEffect(.degrees(-4))
                    .shadow(color: .black.opacity(0.10), radius: 12, y: 6)
            },
            loadMore: { await store.loadFeed() },
            refresh: { await store.loadFeed(refresh: true) }
        )
        .background(palette.bg)
        .navigationTitle("CUTIN")
        /* 인라인 + 워드마크. 큰 제목은 시스템 서체라 로그인·인트로의 Geist 로고와 다른 글자였다
         * (감사 G2). 다른 탭도 인라인이라 상단 높이가 탭마다 달라지지 않는다. */
        .navigationBarTitleDisplayMode(.inline)
        .routeDestinations()
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("CUTIN")
                    .font(Typography.logo(size: 18))
                    .kerning(18 * Typography.logoKerning)
                    .foregroundStyle(palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
            }
            ToolbarItem(placement: .primaryAction) { bell }
        }
        .task {
            await store.loadFeed()
            await notifications.loadUnreadCount()
        }
    }

    /* 알림 진입점. 탭을 만들지 않은 이유는 `NotificationsView` 머리말에 있다.
     *
     * 개수를 숫자로 쓰지 않고 점만 찍는다 — 목록에 들어가면 어차피 다 보이고, 숫자를 쓰면
     * 읽음 처리가 늦게 반영될 때 그 오차가 눈에 띈다. */
    private var bell: some View {
        NavigationLink(value: Route.notifications) {
            Image(systemName: "bell")
                .overlay(alignment: .topTrailing) {
                    if notifications.unread > 0 {
                        Circle()
                            .fill(palette.brand)
                            .frame(width: 8, height: 8)
                            .offset(x: 4, y: -2)
                    }
                }
        }
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
                // 스피너 대신 카드 자리 — 받는 동안에도 화면이 "피드"로 보인다(감사 G4).
                skeleton
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

    /* 카드 두 장의 자리 — 세로 3:4 이미지 자리와 작성자 행. 반짝임은 `Shimmer`. */
    private var skeleton: some View {
        ScrollView {
            VStack(spacing: Spacing.x8) {
                ForEach(0..<2, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: Spacing.x3) {
                        RoundedRectangle(cornerRadius: Radius.md)
                            .fill(palette.surfaceSunken)
                            .aspectRatio(3 / 4, contentMode: .fit)
                            .overlay { Shimmer().clipShape(.rect(cornerRadius: Radius.md)) }
                        HStack(spacing: Spacing.x2) {
                            Circle().fill(palette.surfaceSunken).frame(width: 26, height: 26)
                            RoundedRectangle(cornerRadius: 4).fill(palette.surfaceSunken)
                                .frame(width: 88, height: 12)
                        }
                    }
                }
            }
            .padding(Spacing.x4)
        }
        .scrollDisabled(true)
        .accessibilityLabel("불러오는 중")
    }

    private var content: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.x8) {
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
