/* 로그인 상태 — 앱이 소유하고 모든 화면이 읽는다.
 *
 * 저장된 토큰이 있으면 로그인 화면을 거치지 않는다. `phase`가 `.restoring`으로 시작하는
 * 이유가 이것이다 — Keychain 읽기는 즉시 끝나지만 `/users/me` 확인은 왕복이라, 그 사이 화면을
 * `.signedOut`으로 두면 이미 로그인한 사용자에게 로그인 버튼이 한 번 번쩍인다.
 *
 * **토큰 재발급의 주인은 여기다.** `APIClient`에 재발급 클로저를 심어 두고, 전송 계층이 401을
 * 만나면 이 객체를 거쳐 새 토큰을 받아 Keychain에 남긴다. 반대 방향(전송 계층이 Keychain을
 * 직접 아는 것)으로 두면 둘이 서로를 알게 된다.
 *
 * 온보딩(닉네임)은 다음 브랜치다. 여기서는 서버가 준 `onboardingCompleted`를 그대로 들고만
 * 있는다 — 값을 버리면 그 브랜치가 로그인 응답 처리를 다시 열어야 한다. */

import Foundation
import Observation

@MainActor
@Observable
final class AuthSession {
    enum Phase: Equatable {
        /// 저장된 토큰을 확인하는 중. 앱 시작 직후의 상태다.
        case restoring
        case signedOut
        case signedIn(UserProfile)
    }

    private(set) var phase: Phase = .restoring

    /// 로그인 시도 중. 버튼을 잠그고 표시를 바꾸는 데 쓴다.
    private(set) var isAuthenticating = false

    /// 마지막 실패. 사용자가 취소한 경우는 담지 않는다.
    private(set) var failure: String?

    @ObservationIgnored private let client: APIClient
    @ObservationIgnored private let store = TokenStore()

    init(client: APIClient) {
        self.client = client
    }

    var isSignedIn: Bool {
        if case .signedIn = phase { return true }
        return false
    }

    /// 서버가 온보딩(닉네임)을 마쳤다고 보는지. 다음 브랜치가 이 값으로 분기한다.
    var needsOnboarding: Bool {
        if case .signedIn(let profile) = phase { return !profile.onboardingCompleted }
        return false
    }

    // MARK: - 시작

    /* 앱 시작 시 한 번. 저장된 토큰을 전송 계층에 심고 프로필을 확인한다.
     *
     * 만료된 액세스 토큰이어도 로그인 화면으로 보내지 않는다 — `/users/me`가 401을 내고
     * 전송 계층이 재발급으로 풀어 준다. 리프레시까지 죽었을 때만 로그아웃이다. */
    /* 전송 계층에 재발급 경로를 심는다. `restore()`가 부르지만 따로 떼어 둔 이유는 순서가
     * 중요하기 때문이다 — 토큰을 심기 전에 이것이 먼저 걸려 있어야 첫 요청의 401도 재발급으로
     * 풀린다. 뒤에 걸면 앱 시작 직후의 첫 왕복만 재발급 없이 실패한다. */
    func attachRefresher() async {
        await client.setRefresher { [weak self] in
            guard let self else { throw APIError.transport(CancellationError()) }
            return try await self.refreshTokens()
        }
    }

    func restore() async {
        await attachRefresher()

        guard let tokens = store.load() else {
            phase = .signedOut
            return
        }
        await client.setAccessToken(tokens.accessToken)

        do {
            phase = .signedIn(try await client.send(.get, "/users/me", as: UserProfile.self))
        } catch {
            /* 네트워크가 없어서 실패한 것과 토큰이 죽어서 실패한 것을 가른다.
             * 오프라인일 때 로그아웃시키면 비행기 모드에서 앱을 켠 사용자가 로그인 화면을 보고
             * 다시 로그인할 수도 없다. 토큰은 남겨 두고 다음 시도에 맡긴다. */
            if case APIError.transport = error {
                phase = .signedOut
                failure = "서버에 연결할 수 없어요. 잠시 후 다시 시도해주세요"
            } else {
                await signOutLocally()
            }
        }
    }

    // MARK: - 로그인 · 로그아웃

    func signInWithKakao() async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        failure = nil
        defer { isAuthenticating = false }

        do {
            let kakaoToken = try await KakaoLogin.accessToken()
            let login: LoginResponse = try await client.send(
                .post, "/auth/oauth/kakao",
                body: OAuthLoginBody(token: kakaoToken),
                authorized: false
            )
            persist(access: login.accessToken, refresh: login.refreshToken, expiresIn: login.expiresIn)
            await client.setAccessToken(login.accessToken)
            phase = .signedIn(try await client.send(.get, "/users/me", as: UserProfile.self))
        } catch is CancellationError {
            // 로그인 창을 닫은 것. 오류로 보여주지 않는다.
        } catch {
            failure = message(for: error)
        }
    }

    /* 서버에 로그아웃을 알리되 **결과를 기다려 판단하지 않는다.** 서버가 죽어 있어도 기기에서는
     * 로그아웃돼야 한다 — 실패를 이유로 로그인 상태를 유지하면 사용자가 빠져나갈 수 없다. */
    func signOut() async {
        try? await client.send(.post, "/auth/logout")
        await signOutLocally()
    }

    // MARK: - 내부

    private func signOutLocally() async {
        store.clear()
        await client.setAccessToken(nil)
        phase = .signedOut
    }

    /* 전송 계층이 401에서 부른다. 성공하면 새 액세스 토큰을 돌려주고 Keychain을 갱신한다.
     * 실패하면 로그아웃시킨다 — 리프레시가 죽었으면 다시 로그인하는 수밖에 없다.
     *
     * 서버가 리프레시 토큰도 새로 준다(`TokensResponse`). 회전을 하는 구현일 수 있으므로
     * 받은 것을 반드시 저장해야 한다 — 옛 것을 계속 쓰면 다음 재발급이 거부된다. */
    private func refreshTokens() async throws -> String {
        guard let current = store.load() else {
            await signOutLocally()
            throw APIError.server(
                status: 401, code: APIError.Code.unauthorized.rawValue,
                message: "로그인이 필요합니다.", details: nil
            )
        }
        do {
            let tokens: TokensResponse = try await client.send(
                .post, "/auth/refresh",
                body: RefreshBody(refreshToken: current.refreshToken),
                authorized: false
            )
            persist(access: tokens.accessToken, refresh: tokens.refreshToken,
                    expiresIn: tokens.expiresIn)
            return tokens.accessToken
        } catch {
            // 네트워크 실패로 로그아웃시키지 않는다 — 토큰이 죽은 게 아니다.
            if case APIError.transport = error { throw error }
            await signOutLocally()
            throw error
        }
    }

    private func persist(access: String, refresh: String, expiresIn: Int) {
        store.save(AuthTokens(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: Date.now.addingTimeInterval(TimeInterval(expiresIn))
        ))
    }

    /* 서버가 준 한국어 `message`를 쓴다. 앱이 문구를 따로 지으면 서버가 이유를 바꿔도
     * 화면은 옛 문장을 말한다. 전송 실패만 앱이 문구를 갖는다 — 서버가 응답을 못 준 상황이라
     * 서버 문구가 없다. */
    private func message(for error: any Error) -> String {
        switch error {
        case APIError.transport:
            return "서버에 연결할 수 없어요. 잠시 후 다시 시도해주세요"
        case APIError.server(_, _, let message, _):
            return message
        default:
            return "로그인에 실패했어요. 잠시 후 다시 시도해주세요"
        }
    }
}
