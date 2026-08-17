/* 친구 탭 — 명세 §9.
 *
 * 0.1.0은 "친구 목록은 계정이 붙는 다음 버전에서 열려요" + 초대 공유 하나였다. 서버가 생겼으니
 * 그 약속을 지킨다. 초대 공유는 남긴다 — 아직 친구가 없는 사람에게는 그것이 유일한 다음 행동이다.
 *
 * ## 검색을 먼저 두는 이유
 *
 * 명세 §3.2(온보딩 친구목록 로드)가 🔴로 막혀 있어, 사용자가 친구를 얻는 경로는 **검색과 추천**
 * 둘뿐이다. 목록만 있으면 처음 쓰는 사람에게는 영원히 빈 화면이다.
 *
 * 친구·팔로워·팔로잉을 **한 화면의 세 갈래**로 둔다. 서버 관계 모델이 단방향 팔로우 + 맞팔
 * (=친구)이라 셋이 실제로 다른 목록이고, 탭을 나누면 "왜 친구 탭에 없는 사람이 팔로워지"를
 * 설명할 자리가 사라진다. 기본은 친구다 — 나머지 둘은 궁금할 때 보는 값이다. */

import SwiftUI

struct FriendsView: View {
    @Environment(SocialStore.self) private var social
    @Environment(\.palette) private var palette

    @State private var query = ""
    @State private var scope: Scope = .friends

    /// 세 목록. 서버 관계 모델(단방향 팔로우 + 맞팔=친구)이 그대로 드러난다.
    private enum Scope: String, CaseIterable {
        case friends, followers, followees

        var label: String {
            switch self {
            case .friends: return "친구"
            case .followers: return "팔로워"
            case .followees: return "팔로잉"
            }
        }
    }

    /// 앱 배포 전이라 딥링크 URL이 없다. 링크를 지어내지 않고 문구만 공유한다.
    private let inviteMessage = "같이 컷 남기자! CUTIN에서 4컷 찍고 하루 한 번 공유해요."

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        Group {
            if isSearching {
                searchList
            } else {
                friendList
            }
        }
        .background(palette.bg)
        .navigationTitle(AppTab.friends.title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "닉네임으로 찾기")
        /* 입력이 멈출 때만 보낸다. `.task(id:)`가 값이 바뀌면 이전 작업을 취소하므로
         * 아래 `Task.sleep`이 디바운스가 된다(온보딩 닉네임 확인과 같은 방식). */
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await social.search(query)
        }
        .task { await social.loadRecommended() }
        .routeDestinations()
    }

    // MARK: - 검색 결과

    @ViewBuilder
    private var searchList: some View {
        if social.searchResults.isLoading, social.searchResults.ids.isEmpty {
            ProgressView().tint(palette.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if social.searchResults.ids.isEmpty, social.searchResults.hasLoaded {
            EmptyStateView(
                title: "찾는 사람이 없어요",
                message: "닉네임을 정확히 입력해 보세요",
                systemImage: "magnifyingglass"
            )
        } else {
            List {
                ForEach(social.searchResults.ids, id: \.self) { id in
                    if let user = social.user(id: id) { row(user) }
                }
                if social.searchResults.nextCursor != nil {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .task { await social.searchMore(query) }
                }
            }
            .listStyle(.plain)
        }
    }

    // MARK: - 친구 목록 · 추천

    private var list: SocialStore.List {
        switch scope {
        case .friends: return social.friends
        case .followers: return social.followers
        case .followees: return social.followees
        }
    }

    private func load(refresh: Bool = false) async {
        switch scope {
        case .friends: await social.loadFriends(refresh: refresh)
        case .followers: await social.loadFollowers(refresh: refresh)
        case .followees: await social.loadFollowees(refresh: refresh)
        }
    }

    @ViewBuilder
    private var friendList: some View {
        VStack(spacing: 0) {
            Picker("목록", selection: $scope) {
                ForEach(Scope.allCases, id: \.self) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Spacing.x4)
            .padding(.vertical, Spacing.x2)

            if list.ids.isEmpty, list.hasLoaded, social.recommended.isEmpty {
                emptyState
            } else {
                List {
                    /* 추천은 **친구 갈래에서만** 보여준다. 팔로워 목록에 "이런 친구는 어때요"가
                     * 끼면 그 사람들이 팔로워인 줄 오해한다. */
                    if scope == .friends, !social.recommended.isEmpty {
                        Section("이런 친구는 어때요") {
                            ForEach(social.recommended, id: \.id) { item in
                                recommendedRow(item)
                            }
                        }
                    }
                    Section(scope.label) {
                        ForEach(list.ids, id: \.self) { id in
                            if let user = social.user(id: id) { row(user) }
                        }
                        if list.nextCursor != nil {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .task { await load() }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable { await load(refresh: true) }
            }
        }
        // 갈래를 바꾸면 그 목록을 받는다. 이미 받아 둔 것은 `load`가 걸러 낸다.
        .task(id: scope) { await load() }
    }

    private var emptyState: some View {
        EmptyStateView(
            title: scope == .friends ? "아직 친구가 없어요" : "아직 아무도 없어요",
            message: "닉네임으로 찾거나 초대장을 보내 보세요",
            systemImage: "person.2"
        ) {
            ShareLink(item: inviteMessage) {
                Text("초대장 보내기")
                    .font(Typography.buttonLabel)
                    .padding(.horizontal, Spacing.x5)
                    .padding(.vertical, Spacing.x3)
            }
            .primaryGlassButton(tint: palette.accent)
        }
    }

    private func row(_ user: UserSummary) -> some View {
        NavigationLink(value: Route.userProfile(user.id)) {
            HStack(spacing: Spacing.x3) {
                AvatarView(url: user.avatarUrl, nickname: user.nickname, size: 40)
                Text(user.nickname ?? "이름 없음")
                    .font(Typography.subheadline)
                    .foregroundStyle(palette.textPrimary)
            }
            .padding(.vertical, Spacing.x1)
        }
    }

    /// 추천은 **함께 아는 친구 수**를 함께 보여준다 — 그게 추천의 근거이고, 없으면 왜 떴는지 모른다.
    private func recommendedRow(_ item: RecommendedUsers.Item) -> some View {
        NavigationLink(value: Route.userProfile(item.id)) {
            HStack(spacing: Spacing.x3) {
                AvatarView(url: item.avatarUrl, nickname: item.nickname, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.nickname ?? "이름 없음")
                        .font(Typography.subheadline)
                        .foregroundStyle(palette.textPrimary)
                    if item.mutualFriendCount > 0 {
                        Text("함께 아는 친구 \(item.mutualFriendCount)명")
                            .font(Typography.label)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            }
            .padding(.vertical, Spacing.x1)
        }
    }
}
