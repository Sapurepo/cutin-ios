/* 임시 검증 하니스 — 앱 타깃에 넣어 한 번 돌리고 다시 뺀다.
 *
 * 이 브랜치가 고친 셋을 실제 HTTP로 확인한다. 셋 다 **눈으로는 보이지 않는** 결함이라
 * 화면을 눌러 보는 것으로는 통과 여부를 알 수 없다:
 *
 *   ① `PostStore.loadUser` 교차 오염 — 두 사용자 목록을 동시에 받으면 서로를 덮었다
 *   ② 같은 목록의 동시 요청이 중복으로 나갔다 — `guard !isLoading`이 무력화돼 있었다
 *   ③ 로그아웃 뒤에도 이전 계정 피드가 남았다 — `hasLoaded`가 true라 다시 받지 않는다
 *   ④ 보관·반응·팔로우·차단 실패가 목록 자리에 담겨 화면에 뜨지 않았다
 *
 * ③은 **음성 대조군이 시나리오 안에 들어 있다** — 같은 시나리오에서 `reset()`을 부르기 전과
 * 후를 함께 재므로, 고치기 전 동작이 무엇이었는지가 결과에 그대로 찍힌다.
 *
 * 실행: followupstub.py를 띄우고 SIMCTL_CHILD_FOLLOWUP_CHECK=1 로 앱을 띄운다.
 * Keychain을 쓰지 않으므로 `CODE_SIGNING_ALLOWED=NO`로 빌드해도 된다. */

#if DEBUG
import Foundation

/* 상수를 enum 밖에 둔다. `@MainActor` 타입의 `static let`은 메인 액터에 격리돼, 아래
 * 태스크 그룹의 `@Sendable` 클로저가 참조하면 Swift 6가 막는다. */
private let stub = URL(string: "http://127.0.0.1:8770")!
private let userA = UUID(uuidString: "aaaaaaaa-0000-4000-8000-000000000001")!
private let userB = UUID(uuidString: "bbbbbbbb-0000-4000-8000-000000000002")!

@MainActor
enum FollowupHarness {
    static var isRequested: Bool {
        ProcessInfo.processInfo.environment["FOLLOWUP_CHECK"] == "1"
    }

    private static var failures = 0

    static func run() async {
        await scenarioCrossContamination()
        await scenarioDuplicateRequest()
        await scenarioResetOnAccountSwitch()
        await scenarioFailuresPropagate()
        scenarioAccountChangeHook()

        print("=== 결과: \(failures == 0 ? "전부 통과" : "실패 \(failures)건") ===")
        fflush(stdout)
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - ① 두 사용자 목록을 동시에 받아도 섞이지 않는다

    /* 이전 판은 `scratch` 프로퍼티 하나를 `await` 너머로 공유했다. B의 호출이 그 슬롯을
     * 덮어쓴 뒤 A의 응답이 도착하면 **A의 결과가 B의 자리에** 쓰였다. */
    private static func scenarioCrossContamination() async {
        print("=== ① 동시 loadUser — 목록이 섞이지 않는다 ===")
        await reset()
        let store = PostStore(client: await signedInClient())

        async let a: Void = store.loadUser(id: userA)
        async let b: Void = store.loadUser(id: userB)
        _ = await (a, b)

        let idsA = store.userList(id: userA).ids
        let idsB = store.userList(id: userB).ids

        check("A 목록이 비어 있지 않다", !idsA.isEmpty, "\(idsA.count)건")
        check("B 목록이 비어 있지 않다", !idsB.isEmpty, "\(idsB.count)건")
        check("A 목록에 A의 포스트만 있다",
              idsA.allSatisfy { store.post(id: $0)?.author.id == userA },
              authors(of: idsA, in: store))
        check("B 목록에 B의 포스트만 있다",
              idsB.allSatisfy { store.post(id: $0)?.author.id == userB },
              authors(of: idsB, in: store))
        check("두 목록이 겹치지 않는다", Set(idsA).isDisjoint(with: Set(idsB)))
    }

    // MARK: - ② 같은 목록의 동시 호출은 한 번만 나간다

    private static func scenarioDuplicateRequest() async {
        print("=== ② 같은 사용자 동시 호출 → 요청 1회 ===")
        await reset()
        let store = PostStore(client: await signedInClient())

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<4 {
                group.addTask { await store.loadUser(id: userA) }
            }
        }

        let counts = await state()["userRequests"] as? [String: Int] ?? [:]
        let sent = counts[userA.path] ?? 0
        check("요청이 정확히 1회", sent == 1, "실제 \(sent)회")
        check("목록은 한 페이지분", store.userList(id: userA).ids.count == 2,
              "\(store.userList(id: userA).ids.count)건")
    }

    // MARK: - ③ 계정이 바뀌면 받아 둔 것을 버린다

    /* 음성 대조군 포함. `reset()` **전**에 한 번 더 받아 보면 이전 계정 목록 위에 새 계정
     * 페이지가 덧붙는다 — 고치기 전 사용자가 보던 화면이 그것이다. */
    private static func scenarioResetOnAccountSwitch() async {
        print("=== ③ 계정 전환 — reset 전/후 ===")
        await reset()
        let store = PostStore(client: await signedInClient())

        await store.loadFeed()
        let first = store.feed.ids
        check("A 계정 피드를 받았다", first.count == 2, "\(first.count)건")
        check("전부 A의 것", first.allSatisfy { store.post(id: $0)?.author.id == userA },
              authors(of: first, in: store))

        // 서버 쪽 계정을 바꾼다 = 로그아웃 후 다른 계정으로 로그인
        await set(["account": userB.path])

        // (음성 대조군) 비우지 않고 다시 받으면 — 이전 계정 목록 위에 덧붙는다
        await store.loadFeed()
        let mixed = store.feed.ids
        let hasBoth = mixed.contains { store.post(id: $0)?.author.id == userA }
            && mixed.contains { store.post(id: $0)?.author.id == userB }
        check("(대조군) 비우지 않으면 두 계정이 섞인다 — 고치기 전 동작", hasBoth,
              authors(of: mixed, in: store))

        // 앱이 하는 일: 계정이 바뀌면 버린다
        store.reset()
        check("reset이 목록·커서·포스트를 비운다",
              store.feed.ids.isEmpty && store.feed.nextCursor == nil
                  && !store.feed.hasLoaded && store.posts.isEmpty)

        await store.loadFeed()
        let after = store.feed.ids
        check("다시 받으면 B의 것만", !after.isEmpty
              && after.allSatisfy { store.post(id: $0)?.author.id == userB },
              authors(of: after, in: store))
    }

    // MARK: - ④ 동작 실패가 호출부까지 올라온다

    /* 이전 판은 실패를 `feed.failure`·`searchResults.failure`에 담았다. 그 자리는 **목록이
     * 비었을 때만** 그려지거나(PostList) 아예 그려지지 않아서(UserProfileView), 사용자에게는
     * 버튼이 죽은 것으로 보였다. */
    private static func scenarioFailuresPropagate() async {
        print("=== ④ 보관·반응·팔로우·차단 실패가 던져진다 ===")
        await reset()
        let client = await signedInClient()
        let store = PostStore(client: client)
        let social = SocialStore(client: client)

        await store.loadFeed()
        guard let id = store.feed.ids.first else {
            failures += 1
            print("FAIL  피드를 받지 못해 ④를 돌릴 수 없다")
            return
        }

        await set(["failBookmark": true, "failReaction": true,
                   "failFollow": true, "failBlock": true])

        await expectThrow("보관 실패를 던진다") { try await store.toggleBookmark(id: id) }
        check("보관 실패가 피드 자리에 새지 않는다", store.feed.failure == nil,
              store.feed.failure ?? "")

        await expectThrow("반응 실패를 던진다") { try await store.react(id: id, type: .like) }

        await social.loadProfile(id: userB)
        check("타인 프로필을 받았다", social.profile(id: userB) != nil)

        await expectThrow("팔로우 실패를 던진다") { try await social.toggleFollow(id: userB) }
        await expectThrow("차단 실패를 던진다") { try await social.toggleBlock(id: userB) }
        check("관계 실패가 검색 자리에 새지 않는다", social.searchResults.failure == nil,
              social.searchResults.failure ?? "")

        /* 던진 오류가 **서버 문구를 품고 있는지**. 화면은 `displayMessage(fallback:)`로 이것을
         * 꺼내 쓴다 — 앱이 문구를 지어내면 서버가 이유를 바꿔도 화면은 옛 문장을 말한다. */
        do {
            try await store.toggleBookmark(id: id)
            failures += 1
            print("FAIL  던지지 않았다")
        } catch {
            check("서버 문구를 그대로 전달한다",
                  error.displayMessage(fallback: "앱 문구") == "일시적인 오류입니다.",
                  error.displayMessage(fallback: "앱 문구"))
        }
    }

    // MARK: - ⑤ 계정 변경 훅이 실제로 불린다

    /* ③은 `reset()`이 비우는지를 봤을 뿐, **누가 그것을 부르는가**는 보지 않았다. 훅이 걸리지
     * 않으면 ③의 통과는 아무 의미가 없다.
     *
     * `phase`의 `didSet`으로 부르므로 값이 바뀌는 그 자리에서 불린다 — SwiftUI가 뷰를 다시
     * 그려 주는지에 기대지 않는다. 여기서 재는 것이 그 차이다.
     *
     * 로그인/로그아웃 왕복 없이 `phase`를 직접 움직일 수 없으므로, 세션이 스스로 `signedOut`을
     * 만드는 경로(`restore()`가 저장된 토큰을 못 찾는 경우)를 쓴다. */
    private static func scenarioAccountChangeHook() {
        print("=== ⑤ 계정 변경 훅 ===")
        let session = AuthSession(client: APIClient(baseURL: stub))
        var calls = 0
        session.onAccountChange = { calls += 1 }

        // `restoring` → `signedOut`: 둘 다 userId가 없다. 부르지 않아야 한다.
        session.applyPhaseForTesting(.signedOut)
        check("로그인 전 전이는 부르지 않는다", calls == 0, "\(calls)회")

        session.applyPhaseForTesting(.signedIn(profileForTesting(id: userA)))
        check("로그인하면 부른다", calls == 1, "\(calls)회")

        /* 프로필만 바뀐 경우(닉네임 수정·아바타 교체·온보딩 완료). 여기서 부르면 사용자가
         * 이름을 고칠 때마다 피드가 비워진다. */
        session.applyPhaseForTesting(.signedIn(profileForTesting(id: userA, nickname: "새이름")))
        check("같은 계정의 프로필 수정은 부르지 않는다", calls == 1, "\(calls)회")

        session.applyPhaseForTesting(.signedIn(profileForTesting(id: userB)))
        check("계정이 바뀌면 부른다", calls == 2, "\(calls)회")

        session.applyPhaseForTesting(.signedOut)
        check("로그아웃하면 부른다", calls == 3, "\(calls)회")
    }

    private static func profileForTesting(id: UUID, nickname: String = "네컷러버") -> UserProfile {
        UserProfile(id: id, nickname: nickname, avatarUrl: nil,
                    timezone: "Asia/Seoul", onboardingCompleted: true)
    }

    // MARK: - 보조

    private static func signedInClient() async -> APIClient {
        let client = APIClient(baseURL: stub)
        await client.setAccessToken("GOOD")
        return client
    }

    private static func authors(of ids: [UUID], in store: PostStore) -> String {
        ids.map { store.post(id: $0)?.author.nickname ?? "?" }.joined(separator: ",")
    }

    private static func check(_ label: String, _ passed: Bool, _ detail: String = "") {
        if passed {
            print("PASS  \(label)")
        } else {
            failures += 1
            print("FAIL  \(label)\(detail.isEmpty ? "" : "  — \(detail)")")
        }
    }

    private static func expectThrow(_ label: String, _ call: () async throws -> Void) async {
        do {
            try await call()
            failures += 1
            print("FAIL  \(label)  — 던지지 않았다")
        } catch {
            print("PASS  \(label)")
        }
    }

    private static func reset(_ patch: [String: Any] = [:]) async {
        await post("/__reset", patch)
    }

    private static func set(_ patch: [String: Any]) async {
        await post("/__reset", patch)
    }

    private static func state() async -> [String: Any] {
        guard let (data, _) = try? await URLSession.shared
            .data(from: stub.appending(path: "__state")),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return json
    }

    private static func post(_ path: String, _ body: [String: Any]) async {
        var request = URLRequest(url: stub.appending(path: String(path.dropFirst())))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: request)
    }
}
#endif
