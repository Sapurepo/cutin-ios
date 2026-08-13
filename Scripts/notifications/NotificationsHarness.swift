/* 임시 검증 하니스 — 커밋 전에 삭제한다.
 *
 * 알림에는 조용히 틀리는 자리가 셋 있다:
 *
 *   ① **미읽음 수를 목록에서 세면 안 된다.** 받아 온 페이지 안에서만 참이라, 스크롤하지 않은
 *      사용자에게는 항상 페이지 크기 이하로 보인다. 서버에 전용 엔드포인트가 따로 있다.
 *   ② **읽음은 한 번에 100개까지**다(`maxItems`). 넘겨 보내면 400이고, 그러면 읽은 알림이
 *      영영 안 읽음으로 남는다.
 *   ③ **슬롯은 하나 이상**이어야 한다(`minItems: 1`). 마지막 하나를 끄면 400이라,
 *      "알림 끄기"는 슬롯 비우기가 아니라 `pushEnabled: false`여야 한다.
 *
 * 실행: notifystub.py를 띄우고 SIMCTL_CHILD_NOTIFY_CHECK=1 로 앱을 띄운다. 서명 필요. */

#if DEBUG
import Foundation

@MainActor
enum NotificationsHarness {
    static var isRequested: Bool {
        ProcessInfo.processInfo.environment["NOTIFY_CHECK"] == "1"
    }

    private static let stub = URL(string: "http://127.0.0.1:8771")!
    private static var failures = 0

    static func run() async {
        await scenarioListAndUnread()
        await scenarioMarkRead()
        await scenarioReadBatching()
        await scenarioPreferences()
        await scenarioDevice()

        TokenStore().clear()
        print("=== 결과: \(failures == 0 ? "전부 통과" : "실패 \(failures)건") ===")
        fflush(stdout)
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - ① 목록 · 미읽음 수

    private static func scenarioListAndUnread() async {
        print("=== ① 목록 페이징 · 미읽음 수 ===")
        // 6개 중 5개가 안 읽음. 페이지 크기는 2다.
        await reset(["seedNotifications": 6, "seedUnread": 5])
        let store = await context()

        await store.load()
        check("첫 페이지 2개", store.items.count == 2)

        await store.loadUnreadCount()
        /* 여기가 요점이다. 목록에서 셌다면 2(첫 페이지 안의 안 읽음)가 나온다 —
         * 서버가 세어 준 5여야 한다. */
        check("미읽음은 서버가 센 값", store.unread == 5)

        await store.load()
        await store.load()
        check("끝까지 6개", store.items.count == 6)
        check("커서가 끝났다", store.nextCursor == nil)
        check("중복 없음", Set(store.items.map(\.id)).count == store.items.count)
    }

    // MARK: - ② 읽음 — 본 것만

    private static func scenarioMarkRead() async {
        print("=== ② 읽음 — 화면에 뜬 것만 ===")
        await reset(["seedNotifications": 6, "seedUnread": 6])
        let store = await context()
        await store.load()
        await store.loadUnreadCount()

        // 아무것도 보지 않은 상태에서 flush하면 왕복이 없어야 한다.
        await store.flushRead()
        check("본 것이 없으면 보내지 않는다", (await state())["readCount"] as? Int == 0)

        for item in store.items { store.markVisible(item.id) }
        await store.flushRead()

        let counts = await state()
        check("한 번에 묶어 보낸다", counts["readCount"] as? Int == 1)
        check("본 2개만 보냈다", counts["readIdCount"] as? Int == 2)
        check("목록에 읽음이 반영됐다", store.items.prefix(2).allSatisfy { $0.readAt != nil })
        check("미읽음이 줄었다", store.unread == 4)

        // 이미 읽은 것을 다시 보면 보내지 않는다 — 스크롤할 때마다 왕복이 늘지 않게.
        for item in store.items { store.markVisible(item.id) }
        await store.flushRead()
        check("읽은 것은 다시 보내지 않는다", (await state())["readCount"] as? Int == 1)
    }

    // MARK: - ③ 100개 상한

    private static func scenarioReadBatching() async {
        print("=== ③ 읽음은 한 번에 100개까지 ===")
        // 250개를 한꺼번에 읽으면 3번에 나눠 보내야 한다.
        await reset(["seedNotifications": 250, "seedUnread": 250])
        let store = await context()

        // 페이지를 다 받는다(2개씩 125번).
        while store.nextCursor != nil || !store.hasLoaded {
            await store.load()
        }
        check("250개를 받았다", store.items.count == 250)

        for item in store.items { store.markVisible(item.id) }
        await store.flushRead()

        let counts = await state()
        check("세 번에 나눠 보냈다", counts["readCount"] as? Int == 3)
        /* 한 번에 100개를 넘겨 보내면 서버가 400이고, 그러면 읽은 알림이 영영 안 읽음으로 남는다. */
        check("한 호출의 최대가 100 이하", (counts["maxIdsInOneCall"] as? Int ?? 999) <= 100)
        check("250개를 전부 보냈다", counts["readIdCount"] as? Int == 250)

        await store.loadUnreadCount()
        check("미읽음이 0", store.unread == 0)
    }

    // MARK: - ④ 설정

    private static func scenarioPreferences() async {
        print("=== ④ 알림 설정 — 슬롯은 하나 이상 ===")
        await reset()
        let store = await context()

        await store.loadPreferences()
        check("기본 슬롯은 morning", store.preferences?.slots.first?.known == .morning)
        check("기본은 켜짐", store.preferences?.pushEnabled == true)

        await store.updatePreferences(slots: [.morning, .evening], pushEnabled: true)
        let body = (await state())["lastPrefs"] as? [String: Any] ?? [:]
        check("슬롯 둘을 보냈다", (body["slots"] as? [String])?.sorted() == ["evening", "morning"])
        check("응답을 반영했다", store.preferences?.slots.count == 2)

        /* 빈 슬롯은 **보내지 않는다.** 서버가 400을 내지만, 요청 자체를 막는 편이 낫다 —
         * "알림 끄기"는 슬롯 비우기가 아니라 `pushEnabled: false`다. */
        let before = (await state())["prefsPutCount"] as? Int ?? 0
        await store.updatePreferences(slots: [], pushEnabled: true)
        let after = (await state())["prefsPutCount"] as? Int ?? -1
        check("빈 슬롯은 보내지 않는다", after == before)
        check("설정이 그대로다", store.preferences?.slots.count == 2)

        await store.updatePreferences(slots: [.morning], pushEnabled: false)
        check("끄기는 pushEnabled로", store.preferences?.pushEnabled == false)
        check("슬롯은 남아 있다", store.preferences?.slots.isEmpty == false)
    }

    // MARK: - ⑤ 디바이스

    private static func scenarioDevice() async {
        print("=== ⑤ 디바이스 등록 · 해제 ===")
        await reset()
        let push = PushRegistrar(client: await client())

        // APNs 토큰은 사람이 만들 수 없으므로 바이트를 흉내낸다.
        await push.submit(token: Data([0xDE, 0xAD, 0xBE, 0xEF]))

        var counts = await state()
        check("등록 1회", counts["deviceRegisterCount"] as? Int == 1)
        let body = counts["lastDevice"] as? [String: Any] ?? [:]
        // 토큰은 16진 문자열이어야 한다 — base64나 Data 설명 문자열을 보내면 서버가 못 쓴다.
        check("토큰을 16진으로 보냈다", body["pushToken"] as? String == "deadbeef")
        check("플랫폼은 ios", body["platform"] as? String == "ios")
        check("기기 타임존을 실었다",
              body["timezone"] as? String == TimeZone.current.identifier)

        await push.revoke()
        counts = await state()
        check("해제 1회", counts["deviceRevokeCount"] as? Int == 1)
        // 두 번 지우지 않는다 — 이미 지운 토큰을 또 보내면 서버 왕복만 늘어난다.
        await push.revoke()
        check("토큰이 없으면 다시 보내지 않는다",
              (await state())["deviceRevokeCount"] as? Int == 1)
    }

    // MARK: - 보조

    private static func client() async -> APIClient {
        TokenStore().save(AuthTokens(accessToken: "GOOD", refreshToken: "R1",
                                     expiresAt: Date().addingTimeInterval(3600)))
        let client = APIClient(baseURL: stub)
        await client.setAccessToken("GOOD")
        return client
    }

    private static func context() async -> NotificationStore {
        NotificationStore(client: await client())
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
