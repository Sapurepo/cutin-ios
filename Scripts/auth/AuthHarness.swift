/* 임시 검증 하니스 — 커밋 전에 삭제한다.
 *
 * 카카오 로그인은 사람이 눌러야 해서 자동화할 수 없다. 하지만 **틀리면 조용히 아픈 로직은
 * 로그인 이후**에 있다: 401 → 재발급 → 재시도, 동시 401의 직렬화, 재발급 실패 시 로그아웃,
 * 그리고 오프라인을 로그아웃으로 오해하지 않는 것. 그 넷을 로컬 스텁 서버로 실제 HTTP로 돌린다.
 *
 * 실행: authstub.py를 띄우고 SIMCTL_CHILD_AUTH_CHECK=1 로 앱을 띄운다. */

#if DEBUG
import Foundation
import Security

@MainActor
enum AuthHarness {
    static var isRequested: Bool {
        ProcessInfo.processInfo.environment["AUTH_CHECK"] == "1"
    }

    private static let stub = URL(string: "http://127.0.0.1:8765")!
    /// 아무도 듣지 않는 포트 — 전송 실패를 만든다.
    private static let dead = URL(string: "http://127.0.0.1:8766")!

    private static var failures = 0

    static func run() async {
        let store = TokenStore()

        await scenarioKeychain(store)
        await scenarioRefreshOn401(store)
        await scenarioConcurrentRefresh(store)
        await scenarioRefreshFails(store)
        await scenarioOffline(store)

        store.clear()
        print("=== 결과: \(failures == 0 ? "전부 통과" : "실패 \(failures)건") ===")
        fflush(stdout)
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - ① Keychain

    private static func scenarioKeychain(_ store: TokenStore) async {
        print("=== ① Keychain 왕복 ===")
        // 진단: 실패 시 원인을 알려면 OSStatus가 필요하다
        let probe: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.sapurepo.cutin.probe",
            kSecAttrAccount as String: "probe",
            kSecValueData as String: Data("x".utf8),
        ]
        SecItemDelete(probe as CFDictionary)
        let addStatus = SecItemAdd(probe as CFDictionary, nil)
        print("DIAG  SecItemAdd OSStatus = \(addStatus) (\(SecCopyErrorMessageString(addStatus, nil) as String? ?? "?"))")
        if addStatus == -34018 {
            print("DIAG  → 서명 없이 빌드했다. CODE_SIGNING_ALLOWED=NO로는 Keychain을 쓸 수 없다.")
        }
        SecItemDelete(probe as CFDictionary)

        store.clear()
        check("빈 상태에서 load는 nil", store.load() == nil)

        let first = AuthTokens(accessToken: "A1", refreshToken: "R1",
                               expiresAt: Date(timeIntervalSince1970: 1_000_000))
        check("save 성공", store.save(first))
        check("load가 저장한 값과 같다", store.load() == first)

        /* 두 번째 save가 덮어쓰는지. SecItemAdd만 쓰면 errSecDuplicateItem으로 실패해
         * 옛 토큰이 남고, 계정을 바꿔 로그인했는데 이전 계정으로 붙는다. */
        let second = AuthTokens(accessToken: "A2", refreshToken: "R2",
                                expiresAt: Date(timeIntervalSince1970: 2_000_000))
        check("두 번째 save 성공", store.save(second))
        check("덮어써졌다 (옛 토큰이 남지 않는다)", store.load() == second)

        check("clear 성공", store.clear())
        check("clear 후 nil", store.load() == nil)
        check("항목이 없어도 clear는 성공", store.clear())

        let expired = AuthTokens(accessToken: "A", refreshToken: "R", expiresAt: .now)
        check("만료 판정 (여유 60초)", expired.isExpired())
        let fresh = AuthTokens(accessToken: "A", refreshToken: "R",
                               expiresAt: .now.addingTimeInterval(3600))
        check("유효 판정", !fresh.isExpired())
    }

    // MARK: - ② 401 → 재발급 → 재시도

    private static func scenarioRefreshOn401(_ store: TokenStore) async {
        print("=== ② 401에서 재발급하고 원래 요청을 재시도 ===")
        await reset(expectedAccess: "GOOD", nextAccess: "GOOD2", refreshShouldFail: false)
        seed(store, access: "STALE")

        let session = AuthSession(client: APIClient(baseURL: stub))
        await session.restore()

        check("로그인 상태로 복원됐다", session.isSignedIn)
        let state = await state()
        check("재발급이 정확히 한 번", state.refreshCount == 1, "실제 \(state.refreshCount)")
        check("재시도가 성공해 /users/me가 통과", state.meCount == 1, "실제 \(state.meCount)")
        check("새 토큰이 Keychain에 남았다", store.load()?.accessToken == "GOOD2")
        check("리프레시 토큰도 갱신됐다 (회전 대비)", store.load()?.refreshToken == "R-GOOD2")
    }

    // MARK: - ③ 동시 401이 재발급을 한 번만 부른다

    private static func scenarioConcurrentRefresh(_ store: TokenStore) async {
        print("=== ③ 동시 401 8건 → 재발급 1회 ===")
        await reset(expectedAccess: "GOOD", nextAccess: "GOOD3", refreshShouldFail: false)
        seed(store, access: "STALE")

        let client = APIClient(baseURL: stub)
        let session = AuthSession(client: client)
        // restore를 거치지 않고 재발급 경로만 세운다 — restore의 /users/me가 재발급을
        // 한 번 더 부르면 "동시 401이 몇 번 재발급하는가"의 셈이 흐려진다.
        await session.attachRefresher()
        await client.setAccessToken("STALE")

        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    do {
                        _ = try await client.send(.get, "/templates", as: TemplatesResponse.self)
                        return true
                    } catch {
                        return false
                    }
                }
            }
            var ok = 0
            for await success in group where success { ok += 1 }
            check("8건 모두 성공", ok == 8, "성공 \(ok)건")
        }

        let state = await state()
        check("재발급은 한 번만", state.refreshCount == 1, "실제 \(state.refreshCount)")
    }

    // MARK: - ④ 재발급 실패 → 로그아웃 + Keychain 비움

    private static func scenarioRefreshFails(_ store: TokenStore) async {
        print("=== ④ 재발급이 401 → 로그아웃 ===")
        await reset(expectedAccess: "GOOD", nextAccess: "X", refreshShouldFail: true)
        seed(store, access: "STALE")

        let session = AuthSession(client: APIClient(baseURL: stub))
        await session.restore()

        check("로그아웃 상태", session.phase == .signedOut)
        check("Keychain이 비었다", store.load() == nil)
    }

    // MARK: - ⑤ 오프라인을 로그아웃으로 오해하지 않는다

    private static func scenarioOffline(_ store: TokenStore) async {
        print("=== ⑤ 서버에 닿지 못함 → 토큰은 보존 ===")
        seed(store, access: "STALE")

        let session = AuthSession(client: APIClient(baseURL: dead))
        await session.restore()

        check("로그인 화면으로 간다", session.phase == .signedOut)
        /* 여기가 핵심이다. 오프라인에서 토큰을 지우면 비행기 모드로 앱을 켠 사용자가
         * 로그인 화면을 보고, 로그인도 할 수 없다. */
        check("토큰은 지우지 않았다", store.load()?.accessToken == "STALE")
        check("연결 실패 문구를 보여준다", session.failure != nil)
    }

    // MARK: - 보조

    private static func seed(_ store: TokenStore, access: String) {
        store.save(AuthTokens(accessToken: access, refreshToken: "R1",
                              expiresAt: .now.addingTimeInterval(3600)))
    }

    private struct StubState: Decodable {
        let refreshCount: Int
        let meCount: Int
    }

    private static func state() async -> StubState {
        guard let data = try? await URLSession.shared.data(from: stub.appending(path: "__state")).0,
              let parsed = try? JSONDecoder().decode(StubState.self, from: data)
        else {
            failures += 1
            print("FAIL  스텁 상태를 읽지 못했다 — authstub.py가 떠 있는지 확인")
            return StubState(refreshCount: -1, meCount: -1)
        }
        return parsed
    }

    private static func reset(expectedAccess: String, nextAccess: String,
                              refreshShouldFail: Bool) async {
        var request = URLRequest(url: stub.appending(path: "__reset"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "expectedAccess": expectedAccess,
            "nextAccess": nextAccess,
            "refreshShouldFail": refreshShouldFail,
        ])
        _ = try? await URLSession.shared.data(for: request)
    }

    private static func check(_ label: String, _ passed: Bool, _ detail: String = "") {
        if passed {
            print("PASS  \(label)")
        } else {
            failures += 1
            print("FAIL  \(label)\(detail.isEmpty ? "" : "  — \(detail)")")
        }
    }
}
#endif
