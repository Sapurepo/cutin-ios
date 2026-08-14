/* 임시 검증 하니스 — 커밋 전에 삭제한다.
 *
 * 소셜 API의 함정은 **응답 모양이 오퍼레이션마다 다르다**는 것이다:
 *
 *   POST   /users/:id/follow  → 200 `FollowResult` (본문 있음)
 *   DELETE /users/:id/follow  → **204, 본문 없음**
 *   POST·DELETE /users/:id/block → **204, 본문 없음**
 *
 * 셋을 같은 호출로 묶어 `FollowResult`로 디코드하면 언팔로우·차단이 항상 디코드 실패로 끝난다.
 * **서버에서는 이미 처리된 뒤라** 화면만 "안 된다"고 말하고, 다시 눌러도 같은 일이 반복된다.
 *
 * 차단은 서버가 양방향 팔로우를 함께 끊으므로 앱이 관계를 손으로 맞출 수 없다 —
 * 다시 받아야 한다는 것을 ③이 확인한다.
 *
 * 실행: socialstub.py를 띄우고 SIMCTL_CHILD_SOCIAL_CHECK=1 로 앱을 띄운다. 서명 필요. */

#if DEBUG
import Foundation

@MainActor
enum SocialHarness {
    static var isRequested: Bool {
        ProcessInfo.processInfo.environment["SOCIAL_CHECK"] == "1"
    }

    private static let stub = URL(string: "http://127.0.0.1:8770")!
    private static let postId = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!
    private static var failures = 0

    static func run() async {
        await scenarioFollow()
        await scenarioUnfollow()
        await scenarioBlock()
        await scenarioSearchAndLists()
        await scenarioComments()
        await scenarioReactions()
        await scenarioReport()

        TokenStore().clear()
        print("=== 결과: \(failures == 0 ? "전부 통과" : "실패 \(failures)건") ===")
        fflush(stdout)
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - ① 팔로우

    private static func scenarioFollow() async {
        print("=== ① 팔로우 — 서버가 준 결과를 쓴다 ===")
        // 상대가 이미 나를 팔로우 중이면 누르는 순간 친구가 된다.
        await reset(["seedPeople": 1, "seedFollowsMe": true])
        let social = await context()
        let target = person(0)

        await social.loadProfile(id: target)
        check("처음엔 팔로우 아님", social.profile(id: target)?.following == false)
        check("상대는 나를 팔로우 중", social.profile(id: target)?.followedBy == true)

        await social.toggleFollow(id: target)
        let counts = await state()
        check("POST 1회", counts["followCount"] as? Int == 1)
        check("팔로잉이 됐다", social.profile(id: target)?.following == true)
        /* 친구 여부를 앱이 조합하지 않는다는 것의 확인이다 — 서버가 `friend: true`를 실어 준다. */
        check("맞팔이라 친구가 됐다", social.profile(id: target)?.friend == true)
    }

    // MARK: - ② 언팔로우 (핵심 — 본문이 없다)

    private static func scenarioUnfollow() async {
        print("=== ② 언팔로우 — 204, 본문 없음 ===")
        await reset(["seedPeople": 1, "seedFollowsMe": true])
        let social = await context()
        let target = person(0)

        await social.loadProfile(id: target)
        await social.toggleFollow(id: target)   // 팔로우
        await social.toggleFollow(id: target)   // 언팔로우

        let counts = await state()
        check("DELETE 1회", counts["unfollowCount"] as? Int == 1)
        /* `FollowResult`로 디코드하려 들면 여기서 실패하고 화면 상태가 그대로 남는다 —
         * 서버에서는 이미 끊긴 뒤라 사용자는 "언팔로우가 안 된다"고 본다. */
        check("팔로잉이 풀렸다", social.profile(id: target)?.following == false)
        check("친구도 풀렸다", social.profile(id: target)?.friend == false)
    }

    // MARK: - ③ 차단 (연쇄 효과)

    private static func scenarioBlock() async {
        print("=== ③ 차단 — 팔로우가 함께 끊긴다 ===")
        await reset(["seedPeople": 1, "seedFollowsMe": true])
        let social = await context()
        let target = person(0)

        await social.loadProfile(id: target)
        await social.toggleFollow(id: target)
        check("친구 상태에서 시작", social.profile(id: target)?.friend == true)

        await social.toggleBlock(id: target)
        var counts = await state()
        check("차단 POST 1회", counts["blockCount"] as? Int == 1)
        check("차단됨", social.profile(id: target)?.blocking == true)
        /* 서버가 팔로우를 함께 끊는다. 앱이 `blocking`만 손으로 켰다면 여기가 어긋난다 —
         * 프로필을 다시 받아야만 맞는 값이다. */
        check("팔로우가 함께 끊겼다", social.profile(id: target)?.following == false)
        check("친구도 끊겼다", social.profile(id: target)?.friend == false)

        await social.toggleBlock(id: target)
        counts = await state()
        check("차단 해제 DELETE 1회", counts["unblockCount"] as? Int == 1)
        check("차단이 풀렸다", social.profile(id: target)?.blocking == false)
        // 해제해도 끊긴 팔로우는 복구되지 않는다(컨트롤러 설명).
        check("팔로우는 복구되지 않는다", social.profile(id: target)?.following == false)
    }

    // MARK: - ④ 검색 · 목록

    private static func scenarioSearchAndLists() async {
        print("=== ④ 검색 · 친구 목록 ===")
        await reset(["seedPeople": 5, "seedFollowsMe": true])
        let social = await context()

        await social.search("친구")
        check("검색 첫 페이지 2명", social.searchResults.ids.count == 2)
        check("질의를 실었다", (await state())["lastSearchQuery"] as? String == "친구")

        await social.searchMore("친구")
        check("더 받으면 4명", social.searchResults.ids.count == 4)
        check("중복 없음",
              Set(social.searchResults.ids).count == social.searchResults.ids.count)

        /* 질의가 바뀌면 결과를 갈아끼운다 — 이어 붙이면 이전 질의의 사람이 새 목록에 남는다.
         * 아무도 맞지 않는 질의로 확인한다. */
        await social.search("없는이름")
        check("새 질의는 결과를 갈아끼운다", social.searchResults.ids.isEmpty)

        // 친구는 맞팔만. 팔로우하기 전에는 비어 있어야 한다.
        await social.loadFriends()
        check("팔로우 전에는 친구 없음", social.friends.ids.isEmpty)

        await social.loadProfile(id: person(0))
        await social.toggleFollow(id: person(0))
        /* 팔로우가 친구 목록을 무효화해야 한다 — 그러지 않으면 방금 친구가 된 사람이
         * 목록에 나타나지 않는다. */
        await social.loadFriends()
        check("팔로우 후 친구 목록에 나타난다", social.friends.ids == [person(0)])

        await social.loadRecommended()
        check("추천을 받았다", !social.recommended.isEmpty)
        check("함께 아는 친구 수가 온다", social.recommended.allSatisfy { $0.mutualFriendCount > 0 })
    }

    // MARK: - ⑤ 댓글

    private static func scenarioComments() async {
        print("=== ⑤ 댓글 ===")
        await reset(["seedComments": 3])
        let comments = await commentContext()

        await comments.load(postId: postId)
        check("첫 페이지 2개", comments.list(for: postId).items.count == 2)
        await comments.load(postId: postId)
        check("둘째 페이지까지 3개", comments.list(for: postId).items.count == 3)
        check("커서가 끝났다", comments.list(for: postId).nextCursor == nil)

        let posted = await comments.post(postId: postId, body: "  새 댓글  ")
        check("작성 성공", posted)
        check("앞뒤 공백을 다듬어 보낸다", comments.list(for: postId).items.last?.body == "새 댓글")
        /* 맨 뒤에 붙어야 한다 — 목록이 오래된 순이라 방금 쓴 것이 마지막이다.
         * 앞에 붙이면 다시 받았을 때 순서가 뒤집힌다. */
        check("맨 뒤에 붙었다", comments.list(for: postId).items.count == 4)

        // 빈 댓글은 보내지 않는다 — 서버 왕복을 낭비하지 않는다.
        let before = (await state())["commentPostCount"] as? Int ?? 0
        let empty = await comments.post(postId: postId, body: "   ")
        let after = (await state())["commentPostCount"] as? Int ?? -1
        check("빈 댓글은 보내지 않는다", !empty && after == before)

        if let target = comments.list(for: postId).items.last?.id {
            await comments.delete(postId: postId, commentId: target)
            check("삭제되면 목록에서 빠진다",
                  !comments.list(for: postId).items.contains { $0.id == target })
        }
    }

    // MARK: - ⑥ 반응

    private static func scenarioReactions() async {
        print("=== ⑥ 반응 — 요약 전체를 받아 쓴다 ===")
        await reset()
        let posts = await postContext()
        await seedPost(into: posts)

        await posts.react(id: postId, type: .like)
        var counts = await state()
        check("PUT 1회", counts["reactionPutCount"] as? Int == 1)
        check("내 반응이 like", posts.post(id: postId)?.reactions.mine?.known == .like)
        check("합계 1", posts.post(id: postId)?.reactions.total == 1)

        // 다른 반응이면 교체다 — 지웠다 다시 넣지 않는다.
        await posts.react(id: postId, type: .love)
        counts = await state()
        check("교체는 PUT 하나로", counts["reactionPutCount"] as? Int == 2
              && counts["reactionDeleteCount"] as? Int == 0)
        check("내 반응이 love로 바뀌었다", posts.post(id: postId)?.reactions.mine?.known == .love)
        check("합계는 그대로 1", posts.post(id: postId)?.reactions.total == 1)

        // 같은 반응을 다시 누르면 취소다.
        await posts.react(id: postId, type: .love)
        counts = await state()
        check("취소는 DELETE", counts["reactionDeleteCount"] as? Int == 1)
        check("내 반응이 없다", posts.post(id: postId)?.reactions.mine == nil)
        check("합계 0", posts.post(id: postId)?.reactions.total == 0)
    }

    // MARK: - ⑦ 신고

    private static func scenarioReport() async {
        print("=== ⑦ 신고 ===")
        await reset()
        let social = await context()

        do {
            try await social.report(targetType: .post, targetId: postId,
                                    reason: .spam, detail: "광고예요")
            let body = (await state())["lastReport"] as? [String: Any] ?? [:]
            check("대상 종류를 실었다", body["targetType"] as? String == "post")
            check("사유를 실었다", body["reason"] as? String == "spam")
            check("상세를 실었다", body["detail"] as? String == "광고예요")
        } catch {
            failures += 1
            print("FAIL  신고가 던졌다: \(error)")
        }

        /* 상세가 비면 **키를 아예 빼야 한다.** 빈 문자열을 실으면 서버가 "내용 없음"이 아니라
         * "빈 내용"으로 저장한다. `Field`를 쓰지 않고 nil을 넘기는 이유가 이것이다. */
        do {
            try await social.report(targetType: .user, targetId: postId,
                                    reason: .other, detail: "")
            let body = (await state())["lastReport"] as? [String: Any] ?? [:]
            check("빈 상세는 키를 뺀다", body["detail"] == nil)
        } catch {
            failures += 1
            print("FAIL  신고가 던졌다: \(error)")
        }
    }

    // MARK: - 보조

    private static func person(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "1111%04d-1111-4111-8111-111111111111", index))!
    }

    /// 반응 시나리오가 쓸 포스트를 사전에 넣는다. 스텁의 피드를 흉내낼 필요가 없다.
    private static func seedPost(into store: PostStore) async {
        store.insertPublished(Post(
            id: postId,
            author: PostAuthor(id: UUID(), nickname: "네컷러버", avatarUrl: nil),
            template: Template(id: UUID(), code: "grid4", name: "네 컷", cutCount: 4,
                               aspectRatio: "1:1", slots: []),
            frame: nil, status: ServerEnum(.published), visibility: ServerEnum(.friends),
            caption: nil, thumbnailCutIndex: nil, cuts: [], composed: nil,
            publishedAt: nil, createdAt: "2026-08-13T00:00:00Z", commentCount: 0,
            reactions: ReactionSummary(total: 0, counts: [], mine: nil), bookmarked: false
        ))
    }

    private static func client() async -> APIClient {
        TokenStore().save(AuthTokens(accessToken: "GOOD", refreshToken: "R1",
                                     expiresAt: Date().addingTimeInterval(3600)))
        let client = APIClient(baseURL: stub)
        await client.setAccessToken("GOOD")
        return client
    }

    private static func context() async -> SocialStore {
        SocialStore(client: await client())
    }

    private static func commentContext() async -> CommentStore {
        CommentStore(client: await client())
    }

    private static func postContext() async -> PostStore {
        PostStore(client: await client())
    }

    private static func check(_ name: String, _ passed: Bool) {
        if passed {
            print("PASS  \(name)")
        } else {
            failures += 1
            print("FAIL  \(name)")
        }
    }

    private static func reset(_ patch: [String: Any] = [:]) async {
        var request = URLRequest(url: stub.appending(path: "__reset"))
        request.httpMethod = "POST"
        request.httpBody = try? JSONSerialization.data(withJSONObject: patch)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        _ = try? await URLSession.shared.data(for: request)
    }

    private static func state() async -> [String: Any] {
        guard let (data, _) = try? await URLSession.shared.data(from: stub.appending(path: "__state")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return json
    }
}
#endif
