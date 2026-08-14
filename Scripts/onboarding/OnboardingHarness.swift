/* 임시 검증 하니스 — 커밋 전에 삭제한다.
 *
 * 온보딩 화면은 입력칸 하나지만, 그 뒤에 왕복이 둘 있고 둘 사이에 함정이 있다:
 *
 *   ① 서버의 `isNicknameTaken`이 **자기 자신을 제외하지 않는다.** 이미 저장한 이름을 다시
 *      보내면 자기 이름에 409가 난다. 첫 왕복만 성공하고 둘째가 끊긴 뒤 재시도하는 경로가
 *      실제로 그 상황이고, 앱이 PATCH를 건너뛰지 않으면 사용자는 **다른 이름을 짓기 전까지
 *      온보딩을 마칠 수 없다.**
 *   ② `POST …/onboarding/complete`는 닉네임이 없으면 거절한다. 순서가 뒤바뀌면 통과하지 않는다.
 *
 * 스텁은 실제 백엔드(`usersService.ts`·`nicknamePolicy.ts`)의 거절 조건을 그대로 흉내낸다 —
 * 관대한 스텁으로는 함정을 피하는지 시험할 수 없다.
 *
 * 실행: onboardingstub.py를 띄우고 SIMCTL_CHILD_ONBOARDING_CHECK=1 로 앱을 띄운다.
 * **서명해서 빌드해야 한다** — `restore()`가 Keychain을 읽는다(`Scripts/auth/README.md` 참조). */

#if DEBUG
import Foundation

@MainActor
enum OnboardingHarness {
    static var isRequested: Bool {
        ProcessInfo.processInfo.environment["ONBOARDING_CHECK"] == "1"
    }

    private static let stub = URL(string: "http://127.0.0.1:8767")!
    private static var failures = 0

    static func run() async {
        await scenarioAvailability()
        await scenarioSaveAndComplete()
        await scenarioSameNicknameSkipsPatch()
        await scenarioRetryAfterCompleteFails()
        await scenarioServerRejections()

        TokenStore().clear()
        print("=== 결과: \(failures == 0 ? "전부 통과" : "실패 \(failures)건") ===")
        fflush(stdout)
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - ① 확인 API

    private static func scenarioAvailability() async {
        print("=== ① 닉네임 확인 — 사유 매핑 ===")
        await reset()
        let session = await signedInSession()

        await expect("쓸 수 있는 이름", { try await session.checkNickname("네컷러버") }) {
            $0.available && $0.reason == nil
        }
        await expect("두 글자 미만 → invalidFormat", { try await session.checkNickname("a") }) {
            !$0.available && $0.reason?.known == .invalidFormat
        }
        await expect("금칙어 → forbiddenWord", { try await session.checkNickname("컷인러버") }) {
            !$0.available && $0.reason?.known == .forbiddenWord
        }
        await expect("사용 중 → taken", { try await session.checkNickname("이미쓰는이름") }) {
            !$0.available && $0.reason?.known == .taken
        }

        /* 스펙에 없는 사유. 서버가 값을 추가해도 던지지 않고 원시 문자열을 보존해야 한다 —
         * 여기서 던지면 입력칸이 아무 반응도 하지 않는 화면이 된다. */
        await set(["unknownReason": true])
        await expect("모르는 사유 → 던지지 않고 raw 보존", {
            try await session.checkNickname("아무이름")
        }) {
            !$0.available && $0.reason?.raw == "reserved" && $0.reason?.known == nil
        }
    }

    // MARK: - ② 저장 → 완료

    private static func scenarioSaveAndComplete() async {
        print("=== ② 저장 → 온보딩 완료 ===")
        await reset()
        let session = await signedInSession()

        check("시작 상태는 온보딩 미완료", needsOnboarding(session))

        await session.completeOnboarding(nickname: "네컷러버")

        let counts = await state()
        check("PATCH 1회", counts["patchCount"] as? Int == 1)
        check("complete 1회", counts["completeCount"] as? Int == 1)
        // 프로필을 쓰는 시점이 여기뿐이라 타임존을 같이 싣는다.
        check("기기 타임존을 실었다", counts["lastTimezone"] as? String == TimeZone.current.identifier)

        check("실패 없음", session.failure == nil)
        if case .signedIn(let profile) = session.phase {
            check("닉네임이 프로필에 반영됐다", profile.nickname == "네컷러버")
            check("온보딩이 닫혔다", profile.onboardingCompleted)
        } else {
            check("로그인 상태 유지", false)
        }
    }

    // MARK: - ③ 같은 이름 재제출 (핵심)

    private static func scenarioSameNicknameSkipsPatch() async {
        print("=== ③ 이미 저장된 이름과 같으면 PATCH를 건너뛴다 ===")
        // 이름은 저장됐는데 온보딩이 닫히지 않은 상태 — 둘째 왕복이 끊긴 뒤의 모습이다.
        await reset(["nickname": "네컷러버", "onboardingCompleted": false])
        let session = await signedInSession()

        await session.completeOnboarding(nickname: "네컷러버")

        let counts = await state()
        /* 여기가 함정이다. PATCH를 보내면 서버가 **자기 이름에** 409를 낸다. */
        check("PATCH를 보내지 않았다", counts["patchCount"] as? Int == 0)
        check("complete 1회", counts["completeCount"] as? Int == 1)
        check("실패 없음", session.failure == nil)
        check("온보딩이 닫혔다", {
            if case .signedIn(let profile) = session.phase { return profile.onboardingCompleted }
            return false
        }())
    }

    // MARK: - ④ 완료가 실패한 뒤 재시도

    private static func scenarioRetryAfterCompleteFails() async {
        print("=== ④ complete 실패 → 재시도 ===")
        await reset(["completeShouldFail": true])
        let session = await signedInSession()

        await session.completeOnboarding(nickname: "네컷러버")

        var counts = await state()
        check("1차: PATCH 1회", counts["patchCount"] as? Int == 1)
        check("1차: 서버 문구를 그대로 담는다", session.failure == "일시적인 오류입니다.")
        /* PATCH 결과를 곧바로 phase에 넣기 때문에, 둘째가 실패해도 "이름은 저장됐다"가 남는다.
         * 그래야 재시도가 ③의 경로로 들어간다. */
        check("1차: 닉네임은 프로필에 남았다", {
            if case .signedIn(let profile) = session.phase { return profile.nickname == "네컷러버" }
            return false
        }())
        check("1차: 온보딩은 닫히지 않았다", needsOnboarding(session))

        await set(["completeShouldFail": false])
        await session.completeOnboarding(nickname: "네컷러버")

        counts = await state()
        check("2차: PATCH가 늘지 않았다", counts["patchCount"] as? Int == 1)
        check("2차: complete 2회", counts["completeCount"] as? Int == 2)
        check("2차: 온보딩이 닫혔다", !needsOnboarding(session))
        check("2차: 실패 문구가 지워졌다", session.failure == nil)
    }

    // MARK: - ⑤ 서버 거절

    private static func scenarioServerRejections() async {
        print("=== ⑤ 서버 거절 — 문구는 서버가 소유한다 ===")
        await reset()
        var session = await signedInSession()

        await session.completeOnboarding(nickname: "이미쓰는이름")
        var counts = await state()
        check("409: complete까지 가지 않는다", counts["completeCount"] as? Int == 0)
        check("409: 서버 문구", session.failure == "이미 사용 중인 닉네임입니다.")
        check("409: 온보딩 화면에 남는다", needsOnboarding(session))

        await reset()
        session = await signedInSession()
        await session.completeOnboarding(nickname: "컷인러버")
        counts = await state()
        check("400: complete까지 가지 않는다", counts["completeCount"] as? Int == 0)
        check("400: 서버 문구", session.failure == "사용할 수 없는 닉네임입니다.")
    }

    // MARK: - 보조

    /// 스텁을 향하는 세션을 만들고 로그인 상태로 만든다.
    private static func signedInSession() async -> AuthSession {
        let store = TokenStore()
        store.save(AuthTokens(accessToken: "GOOD", refreshToken: "R1",
                              expiresAt: Date().addingTimeInterval(3600)))
        let session = AuthSession(client: APIClient(baseURL: stub))
        await session.restore()
        return session
    }

    /// 온보딩이 아직 안 닫혔는지. `AuthGate`는 프로필을 직접 읽어 가르므로 세션에는 두지 않는다.
    private static func needsOnboarding(_ session: AuthSession) -> Bool {
        if case .signedIn(let profile) = session.phase { return !profile.onboardingCompleted }
        return false
    }

    private static func check(_ name: String, _ passed: Bool) {
        if passed {
            print("PASS  \(name)")
        } else {
            failures += 1
            print("FAIL  \(name)")
        }
    }

    private static func expect(
        _ name: String,
        _ call: () async throws -> NicknameAvailability,
        _ passed: (NicknameAvailability) -> Bool
    ) async {
        do {
            check(name, passed(try await call()))
        } catch {
            failures += 1
            print("FAIL  \(name)  던졌다: \(error)")
        }
    }

    private static func reset(_ patch: [String: Any] = [:]) async {
        _ = try? await post("/__reset", patch)
    }

    private static func set(_ patch: [String: Any]) async {
        _ = try? await post("/__set", patch)
    }

    private static func state() async -> [String: Any] {
        guard let (data, _) = try? await URLSession.shared.data(from: stub.appending(path: "__state")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return json
    }

    @discardableResult
    private static func post(_ path: String, _ body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: stub.appending(path: String(path.dropFirst())))
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await URLSession.shared.data(for: request).0
    }
}
#endif
