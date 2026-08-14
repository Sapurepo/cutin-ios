/* 임시 검증 하니스 — 커밋 전에 삭제한다.
 *
 * 발행은 컷 4장 기준 **왕복 열여섯 번**이고, 서버가 단계마다 거절 조건을 갖는다:
 *
 *   - `POST /posts`는 계정당 draft 하나만 만든다 (409 `DRAFT_ALREADY_EXISTS`)
 *   - `PATCH`의 `cuts`는 **ready이고 kind가 cut인 내 미디어**만 받는다
 *   - `publish`는 컷이 템플릿 수만큼 차 있고 합성본이 ready여야 한다
 *
 * 그래서 순서가 하나라도 어긋나면 마지막 왕복에서 실패한다 — 사용자에게는 "컷을 다 찍었는데
 * 저장이 안 된다"로 보인다. 스텁이 그 조건을 그대로 흉내내므로 **통과 자체가 순서의 증거**다.
 *
 * 실행: poststub.py를 띄우고 SIMCTL_CHILD_POSTS_CHECK=1 로 앱을 띄운다. 서명해서 빌드해야 한다. */

#if DEBUG
import UIKit

@MainActor
enum PostsHarness {
    static var isRequested: Bool {
        ProcessInfo.processInfo.environment["POSTS_CHECK"] == "1"
    }

    private static let stub = URL(string: "http://127.0.0.1:8769")!
    private static var failures = 0

    static func run() async {
        await scenarioPublish()
        await scenarioResumeOrphanDraft()
        await scenarioPublishRejections()
        await scenarioFeedPaging()
        await scenarioBookmark()
        await scenarioDeleteAndShare()

        TokenStore().clear()
        print("=== 결과: \(failures == 0 ? "전부 통과" : "실패 \(failures)건") ===")
        fflush(stdout)
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - ① 발행 한 바퀴

    private static func scenarioPublish() async {
        print("=== ① 발행 — draft → 컷 → PATCH → 합성본 → publish ===")
        await reset()
        let (publisher, store) = await context()

        do {
            let post = try await publisher.publish(request(caption: "첫 컷인",
                                                           visibility: .public))
            let counts = await state()
            check("draft 1회", counts["createCount"] as? Int == 1)
            check("PATCH 1회", counts["patchCount"] as? Int == 1)
            check("publish 1회", counts["publishCount"] as? Int == 1)
            /* 컷 인덱스가 0..<N으로 빠짐없이 갔는지. 순서가 어긋나면 스텁이 400을 내므로
             * 여기까지 온 것만으로도 절반은 증명되지만, 값 자체도 확인한다. */
            check("컷 인덱스 0..3", counts["lastCuts"] as? [Int] == [0, 1, 2, 3])
            check("캡션을 PATCH에 실었다", counts["lastCaption"] as? String == "첫 컷인")
            check("프레임을 PATCH에 실었다", counts["lastFrameId"] as? String != nil)
            check("공개 범위를 publish에 실었다", counts["lastVisibility"] as? String == "public")
            check("발행 결과가 published", post.status.known == .published)
            check("합성본이 붙었다", post.composed != nil)
            check("컷 4장이 붙었다", post.cuts.count == 4)

            store.insertPublished(post)
            check("피드 맨 앞에 놓였다", store.feed.ids.first == post.id)
        } catch {
            failures += 1
            print("FAIL  발행이 던졌다: \(error)")
        }
    }

    // MARK: - ② 남은 draft 이어 쓰기 (핵심)

    private static func scenarioResumeOrphanDraft() async {
        print("=== ② 서버에 draft가 남아 있으면 이어 쓴다 ===")
        /* 발행이 중간에 끊긴 상태를 만든다 — draft만 있고 컷이 붙지 않은 모양이다.
         * 스텁이 직접 심는다: 하니스가 `POST /posts`로 만들면 그 호출이 카운터를 올려
         * "앱이 몇 번 만들려 했는가"를 셀 수 없다. */
        await reset(["seedDraft": true])
        let (publisher, _) = await context()

        do {
            _ = try await publisher.publish(request(caption: "이어 쓴 것", visibility: .friends))
            let counts = await state()
            /* `POST /posts`는 409를 받고, `GET /posts/draft`로 넘어가야 한다.
             * 이 처리가 없으면 발행 자체가 409로 죽어 **사용자가 영영 저장할 수 없다.** */
            check("POST /posts를 시도했다", counts["createCount"] as? Int == 1)
            check("409에서 GET /posts/draft로 넘어갔다", counts["getDraftCount"] as? Int == 1)
            check("발행까지 갔다", counts["publishCount"] as? Int == 1)
        } catch {
            failures += 1
            print("FAIL  이어 쓰기가 던졌다: \(error)")
        }
    }

    // MARK: - ③ 서버 거절

    private static func scenarioPublishRejections() async {
        print("=== ③ 컷이 모자라면 서버가 막는다 ===")
        await reset()
        let (publisher, _) = await context()

        /* 컷을 2장만 넣는다. 템플릿이 4컷이므로 `CUTS_INCOMPLETE`가 나야 한다 —
         * 앱이 컷 수를 검사하지 않아도 서버가 막는다는 것을 확인한다. */
        do {
            _ = try await publisher.publish(request(caption: "", visibility: .friends,
                                                    cutCount: 2))
            failures += 1
            print("FAIL  컷이 모자란데 발행됐다")
        } catch let error as APIError {
            check("서버 문구를 그대로 받는다",
                  error.serverMessage == "컷 4장을 모두 채워야 발행할 수 있습니다.")
        } catch {
            failures += 1
            print("FAIL  예상 밖 오류: \(error)")
        }
    }

    // MARK: - ④ 커서 페이징

    private static func scenarioFeedPaging() async {
        print("=== ④ 피드 커서 페이징 ===")
        // 스텁 페이지 크기가 2라 5개면 세 페이지다.
        await reset(["seedPublished": 5])
        let (_, store) = await context()

        await store.loadFeed()
        check("첫 페이지 2개", store.feed.ids.count == 2)
        check("다음 커서가 있다", store.feed.nextCursor != nil)

        await store.loadFeed()
        check("둘째 페이지까지 4개", store.feed.ids.count == 4)

        await store.loadFeed()
        check("마지막 페이지까지 5개", store.feed.ids.count == 5)
        check("커서가 끝났다", store.feed.nextCursor == nil)
        // 같은 id가 두 번 들어가면 ForEach가 목록을 잘못 그린다.
        check("중복 없음", Set(store.feed.ids).count == store.feed.ids.count)

        await store.loadFeed()
        check("끝난 뒤 더 부르면 그대로", store.feed.ids.count == 5)

        await store.loadFeed(refresh: true)
        check("새로고침은 첫 페이지로 돌아간다", store.feed.ids.count == 2)
    }

    // MARK: - ⑤ 보관

    private static func scenarioBookmark() async {
        print("=== ⑤ 보관 — 서버가 준 상태를 쓴다 ===")
        await reset(["seedPublished": 1])
        let (_, store) = await context()
        await store.loadFeed()
        guard let id = store.feed.ids.first else {
            failures += 1
            print("FAIL  표본 포스트가 없다")
            return
        }

        check("처음엔 보관 아님", store.post(id: id)?.bookmarked == false)
        await store.toggleBookmark(id: id)
        check("보관됨", store.post(id: id)?.bookmarked == true)

        await store.loadBookmarks()
        check("보관 목록에 있다", store.bookmarks.ids == [id])

        await store.toggleBookmark(id: id)
        check("보관 해제됨", store.post(id: id)?.bookmarked == false)

        let counts = await state()
        check("PUT 1회 · DELETE 1회",
              counts["bookmarkPutCount"] as? Int == 1
              && counts["bookmarkDeleteCount"] as? Int == 1)

        /* 토글이 보관 목록을 무효화해야 한다 — 그러지 않으면 방금 해제한 포스트가
         * 보관 탭에 남는다(커서 키가 보관 시각이라 목록을 직접 고칠 수 없다). */
        await store.loadBookmarks()
        check("해제 후 목록에서 빠진다", store.bookmarks.ids.isEmpty)
    }

    // MARK: - ⑥ 삭제 · 공유

    private static func scenarioDeleteAndShare() async {
        print("=== ⑥ 삭제 · 공유 링크 ===")
        await reset(["seedPublished": 2])
        let (_, store) = await context()
        await store.loadFeed()
        guard let id = store.feed.ids.first else {
            failures += 1
            print("FAIL  표본 포스트가 없다")
            return
        }

        do {
            let url = try await store.shareLink(id: id)
            check("공유 링크를 받았다", url.absoluteString.contains("/p/\(id.path)"))
        } catch {
            failures += 1
            print("FAIL  공유 링크가 던졌다: \(error)")
        }

        do {
            try await store.delete(id: id)
            check("목록에서 빠졌다", !store.feed.ids.contains(id))
            check("사전에서도 빠졌다", store.post(id: id) == nil)
        } catch {
            failures += 1
            print("FAIL  삭제가 던졌다: \(error)")
        }

        // 지워진 포스트를 다시 받으면 404다. 화면이 "볼 수 없는 포스트"를 그려야 한다.
        await store.refresh(id: id)
        check("404 뒤에도 사전에 되살아나지 않는다", store.post(id: id) == nil)
    }

    // MARK: - 보조

    private static func request(
        caption: String, visibility: PostVisibility, cutCount: Int = 4
    ) -> PostPublisher.Request {
        PostPublisher.Request(
            template: template, frame: frame,
            cuts: (0..<cutCount).map { _ in solid(40, 40) },
            composed: solid(120, 120),
            caption: caption, visibility: visibility
        )
    }

    private static let template = Template(
        id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
        code: "grid4", name: "네 컷", cutCount: 4, aspectRatio: "1:1",
        slots: [(0.0, 0.0), (0.5, 0.0), (0.0, 0.5), (0.5, 0.5)].map {
            TemplateSlot(x: $0.0, y: $0.1, width: 0.5, height: 0.5)
        }
    )

    private static let frame = Frame(
        id: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
        code: "basic", name: "베이직", background: "#1E1E21", foreground: "#F5F5F4",
        padding: 0.0111, gutter: 0.0111, cellRadius: 0.0083, footer: nil
    )

    private static func context() async -> (PostPublisher, PostStore) {
        TokenStore().save(AuthTokens(accessToken: "GOOD", refreshToken: "R1",
                                     expiresAt: Date().addingTimeInterval(3600)))
        let client = APIClient(baseURL: stub)
        let session = AuthSession(client: client)
        await session.restore()
        return (PostPublisher(client: client), PostStore(client: client))
    }

    private static func solid(_ width: Int, _ height: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
            .image { _ in
                UIColor.systemPink.setFill()
                UIRectFill(CGRect(x: 0, y: 0, width: width, height: height))
            }
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
