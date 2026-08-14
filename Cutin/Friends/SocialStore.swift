/* 친구 관계 — 명세 §9. 서버가 소유하므로 앱은 받아 그리고 토글만 한다.
 *
 * `PostStore`와 같은 모양이다: 목록은 **id 배열**, 사용자는 사전에 한 벌.
 * 같은 사람이 친구 목록·검색 결과·추천에 동시에 있고, 한 곳에서 팔로우하면 셋 다 따라가야 한다.
 *
 * ## 관계를 앱이 계산하지 않는다
 *
 * `PublicProfile`이 `following`·`followedBy`·`friend`·`blocking` 네 값을 준다. `friend`는
 * `following && followedBy`처럼 보이지만 **서버가 따로 실어 주므로 그것을 쓴다** — 앱이 계산하면
 * 서버가 친구 정의를 바꿀 때(차단 고려 등) 화면만 옛 규칙을 따른다.
 *
 * 관계를 바꾼 뒤에도 **서버가 만든 상태를 받아 쓴다.** 팔로우는 `FollowResult`가 오고,
 * 본문이 없는 나머지(언팔로우·차단·해제)는 프로필을 다시 받는다. 눌린 값을 뒤집어 짐작하면
 * 두 기기에서 같은 사람을 눌렀을 때 어긋나고, 차단처럼 **연쇄 효과가 있는 동작**
 * (팔로우가 함께 끊긴다)에서는 짐작이 아예 틀린다. */

import Foundation
import Observation

@MainActor
@Observable
final class SocialStore {
    struct List {
        var ids: [UUID] = []
        var nextCursor: String?
        var isLoading = false
        var hasLoaded = false
        var failure: String?

        var canLoadMore: Bool { nextCursor != nil && !isLoading }

        mutating func invalidate() {
            ids = []
            nextCursor = nil
            hasLoaded = false
        }
    }

    private(set) var users: [UUID: UserSummary] = [:]
    /// 타인 프로필. 목록 항목(`UserSummary`)보다 많은 것을 담아 따로 둔다.
    private(set) var profiles: [UUID: PublicProfile] = [:]

    private(set) var friends = List()
    private(set) var followers = List()
    private(set) var followees = List()
    private(set) var searchResults = List()
    private(set) var recommended: [RecommendedUsers.Item] = []
    private(set) var isLoadingRecommended = false

    @ObservationIgnored private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func user(id: UUID) -> UserSummary? { users[id] }
    func profile(id: UUID) -> PublicProfile? { profiles[id] }

    // MARK: - 목록

    private func load(
        _ list: ReferenceWritableKeyPath<SocialStore, List>,
        path: String,
        query: [String: String] = [:],
        refresh: Bool
    ) async {
        guard !self[keyPath: list].isLoading else { return }
        if !refresh, !self[keyPath: list].canLoadMore, self[keyPath: list].hasLoaded { return }

        let cursor = refresh ? nil : self[keyPath: list].nextCursor
        let generation = generation
        self[keyPath: list].isLoading = true
        self[keyPath: list].failure = nil
        defer {
            if generation == self.generation { self[keyPath: list].isLoading = false }
        }

        do {
            var query = query
            if let cursor { query["cursor"] = cursor }
            let page = try await client.send(.get, path, query: query, as: UserPage.self)
            // 기다리는 사이 계정이 바뀌었으면 이전 계정의 관계다(`reset()` 참고).
            guard generation == self.generation else { return }
            for item in page.items { users[item.id] = item }

            let ids = page.items.map(\.id)
            if refresh {
                self[keyPath: list].ids = ids
            } else {
                let known = Set(self[keyPath: list].ids)
                self[keyPath: list].ids += ids.filter { !known.contains($0) }
            }
            self[keyPath: list].nextCursor = page.nextCursor
            self[keyPath: list].hasLoaded = true
        } catch {
            guard generation == self.generation else { return }
            self[keyPath: list].failure = message(for: error)
        }
    }

    func loadFriends(refresh: Bool = false) async {
        await load(\.friends, path: "/users/me/friends", refresh: refresh)
    }

    func loadFollowers(refresh: Bool = false) async {
        await load(\.followers, path: "/users/me/followers", refresh: refresh)
    }

    func loadFollowees(refresh: Bool = false) async {
        await load(\.followees, path: "/users/me/followees", refresh: refresh)
    }

    /* 검색. 질의가 바뀌면 **결과를 통째로 갈아끼운다** — 이어 붙이면 이전 질의의 결과가
     * 새 질의의 목록에 남는다. 디바운스는 화면이 `.task(id:)`로 한다. */
    func search(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            searchResults.invalidate()
            return
        }
        await load(\.searchResults, path: "/users/search", query: ["q": trimmed], refresh: true)
    }

    func searchMore(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        await load(\.searchResults, path: "/users/search", query: ["q": trimmed], refresh: false)
    }

    func loadRecommended() async {
        guard !isLoadingRecommended, recommended.isEmpty else { return }
        isLoadingRecommended = true
        let generation = generation
        defer { isLoadingRecommended = false }
        // 실패는 삼킨다 — 추천은 없어도 되는 목록이고, 화면에 자리도 없다.
        let items = (try? await client.send(
            .get, "/users/recommended", as: RecommendedUsers.self
        ))?.items ?? []
        guard generation == self.generation else { return }
        recommended = items
    }

    // MARK: - 한 사람

    func loadProfile(id: UUID) async {
        let generation = generation
        do {
            let profile = try await client.send(
                .get, "/users/\(id.path)", as: PublicProfile.self
            )
            guard generation == self.generation else { return }
            profiles[id] = profile
        } catch let error as APIError where error.isNotFound {
            guard generation == self.generation else { return }
            profiles[id] = nil
        } catch {
            // 이미 그리고 있는 값이 있으면 그대로 둔다.
        }
    }

    // MARK: - 관계 바꾸기

    /* 팔로우·언팔로우. **응답 모양이 다르다.**
     *
     * `POST`는 `FollowResult`를 주지만 `DELETE`는 **204에 본문이 없다.** 둘을 같은 호출로
     * 묶어 `FollowResult`로 디코드하면 언팔로우가 항상 디코드 실패로 끝난다 — 화면에는
     * "언팔로우가 안 된다"로 보이지만 서버에서는 이미 끊긴 뒤다.
     *
     * 그래서 언팔로우는 프로필을 다시 받는다. 관계를 손으로 맞추지 않는 이유는 위 머리말과
     * 같다 — 왕복 하나를 아끼려고 서버 규칙의 사본을 만들지 않는다.
     *
     * 실패를 `searchResults.failure`에 담지 않고 **던진다.** 그 자리는 검색 목록의 것이라 타인
     * 프로필 화면이 읽지 않는다 — 담아 두면 팔로우가 실패해도 화면에 아무 일도 일어나지 않고,
     * 엉뚱하게 나중에 검색 결과 자리에 옛 문구가 뜬다. */
    func toggleFollow(id: UUID) async throws {
        guard let profile = profiles[id] else { return }
        if profile.following {
            try await client.send(.delete, "/users/\(id.path)/follow")
            await loadProfile(id: id)
        } else {
            let result = try await client.send(
                .post, "/users/\(id.path)/follow", as: FollowResult.self
            )
            profiles[id] = profile.replacing(following: result.following,
                                             friend: result.friend)
        }
        // 친구 목록이 달라졌다. 커서 목록이라 직접 고치지 않고 다시 받는다.
        friends.invalidate()
        followees.invalidate()
    }

    /// 차단·해제. 둘 다 본문 없이 204다.
    ///
    /// 차단하면 **서버가 양방향 팔로우와 친구 관계를 함께 끊는다**(컨트롤러 설명).
    /// 해제해도 끊긴 팔로우는 복구되지 않는다 — 앱이 맞출 수 있는 상태가 아니라 다시 받는다.
    ///
    /// 실패는 `toggleFollow`와 같은 이유로 던진다.
    func toggleBlock(id: UUID) async throws {
        guard let profile = profiles[id] else { return }
        try await client.send(
            profile.blocking ? .delete : .post, "/users/\(id.path)/block"
        )
        /* 차단하면 서버가 팔로우 관계도 끊는다. 프로필을 다시 받아 **서버가 만든 상태**를
         * 그대로 쓴다 — 여기서 네 값을 손으로 맞추면 서버 규칙의 사본이 하나 더 생긴다. */
        await loadProfile(id: id)
        friends.invalidate()
        followees.invalidate()
        followers.invalidate()
    }

    // MARK: - 신고 (§1-7)

    func report(targetType: ReportTargetType, targetId: UUID,
                reason: ReportReason, detail: String) async throws {
        _ = try await client.send(
            .post, "/reports",
            body: CreateReportBody(
                targetType: ServerEnum(targetType),
                targetId: targetId,
                reason: ServerEnum(reason),
                detail: detail.isEmpty ? nil : .value(detail)
            ),
            as: Report.self
        )
    }

    /* 계정이 바뀌었다. 관계는 **보는 사람 기준**이라(`following`·`friend`·`blocking`) 한 줄도
     * 남길 수 없다 — 이전 계정의 친구 목록과 관계 표시가 그대로 새 계정 화면에 뜬다. */
    func reset() {
        generation += 1
        users = [:]
        profiles = [:]
        friends = List()
        followers = List()
        followees = List()
        searchResults = List()
        recommended = []
    }

    /// 계정 세대. 날아가 있던 요청이 비운 자리를 되살리지 않도록 한다(`PostStore`와 같다).
    @ObservationIgnored private var generation = 0

    private func message(for error: any Error) -> String {
        switch error {
        case APIError.transport:
            return "서버에 연결할 수 없어요. 잠시 후 다시 시도해주세요"
        case APIError.server(_, _, let message, _):
            return message
        default:
            return "불러오지 못했어요. 잠시 후 다시 시도해주세요"
        }
    }
}

private extension PublicProfile {
    /// 관계만 바꾼 사본. 응답 타입이 전부 `let`이라 이 자리에서 만든다.
    func replacing(following: Bool, friend: Bool) -> PublicProfile {
        PublicProfile(
            id: id, nickname: nickname, avatarUrl: avatarUrl, friendCount: friendCount,
            following: following, followedBy: followedBy, friend: friend, blocking: blocking
        )
    }
}
