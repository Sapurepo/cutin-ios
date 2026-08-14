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
 * 온보딩(§3.1)과 프로필 수정(§3.4·§8.1)도 여기 있다. 셋 다 **로그인한 사용자 자신의 계정**을
 * 다루고 결과가 `phase`의 프로필로 돌아오므로, 화면에 두면 프로필의 주인이 둘이 된다. */

import Observation
import UIKit
import os

/* 실패한 오류 **자체**를 남긴다. 화면 문구는 카카오 SDK 오류를 "로그인에 실패했어요" 한 문장으로
 * 뭉개므로(`message(for:)`의 default), 이것이 없으면 앱 키·번들 ID·동의항목 중 무엇이 틀렸는지
 * 알 방법이 없다 — 재현해도 남는 것이 그 한 문장뿐이다. */
private let authLog = Logger(subsystem: "com.sapurepo.cutin", category: "auth")

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

    /// 서버에 계정 관련 요청을 보내는 중(로그인·온보딩). 버튼을 잠그고 표시를 바꾸는 데 쓴다.
    /// 두 화면은 `phase`로 갈려 동시에 뜨지 않으므로 깃발 하나로 충분하다.
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

    /// 로그인한 사용자의 id. "내 포스트인가"를 가르는 데 화면들이 쓴다.
    var userId: UUID? {
        if case .signedIn(let profile) = phase { return profile.id }
        return nil
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
            authLog.error("카카오 로그인 실패: \(String(describing: error), privacy: .public)")
            failure = message(for: error)
        }
    }

    /* 서버에 로그아웃을 알리되 **결과를 기다려 판단하지 않는다.** 서버가 죽어 있어도 기기에서는
     * 로그아웃돼야 한다 — 실패를 이유로 로그인 상태를 유지하면 사용자가 빠져나갈 수 없다. */
    func signOut() async {
        try? await client.send(.post, "/auth/logout")
        await signOutLocally()
    }

    // MARK: - 온보딩 (§3.1)

    /* 닉네임 확인과 저장이 화면이 아니라 여기 있는 이유: 둘 다 **로그인한 사용자 자신의 계정**을
     * 다루고, 저장 결과가 `phase`의 프로필로 돌아온다. 화면에 두면 프로필의 주인이 둘이 되고,
     * 전송 계층도 둘이 들게 된다. 키 입력·디바운스 같은 화면 상태는 화면에 남는다. */
    func checkNickname(_ nickname: String) async throws -> NicknameAvailability {
        try await client.send(
            .get, "/users/nickname/availability",
            query: ["nickname": nickname], as: NicknameAvailability.self
        )
    }

    /* 닉네임을 저장하고 온보딩을 닫는다. 왕복이 둘인 이유는 서버가
     * `POST /users/me/onboarding/complete`에서 닉네임이 없으면 거절하기 때문이다(`NICKNAME_REQUIRED`).
     *
     * **저장된 이름과 같으면 PATCH를 건너뛴다.** 서버의 `isNicknameTaken`이 자기 자신을 제외하지
     * 않아서, 같은 이름을 다시 보내면 **자기 이름에 409**가 난다. 첫 왕복만 성공하고 둘째가
     * 끊긴 뒤 재시도하는 경로가 실제로 그 상황이다.
     *
     * PATCH 결과를 곧바로 `phase`에 넣는 것도 같은 이유다 — 둘째가 실패해도 "이름은 저장됐고
     * 온보딩만 안 닫혔다"는 상태가 남아, 다시 눌렀을 때 PATCH를 건너뛰고 이어진다.
     *
     * 타임존을 같이 싣는다. 서버 기본값이 `Asia/Seoul`이고 알림 발송이 이 값을 쓰는데, 프로필을
     * 쓰는 시점이 여기뿐이라 지금 넣지 않으면 다른 시간대의 사용자가 서울 시각으로 알림을 받는다. */
    func completeOnboarding(nickname: String) async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        failure = nil
        defer { isAuthenticating = false }

        do {
            if case .signedIn(let profile) = phase, profile.nickname != nickname {
                phase = .signedIn(try await client.send(
                    .patch, "/users/me",
                    body: UpdateMeBody(nickname: nickname, timezone: TimeZone.current.identifier),
                    as: UserProfile.self
                ))
            }
            phase = .signedIn(try await client.send(
                .post, "/users/me/onboarding/complete", as: UserProfile.self
            ))
        } catch {
            failure = message(for: error)
        }
    }

    // MARK: - 프로필 수정 (§3.4 · §8.1)

    /* 온보딩을 마친 뒤 닉네임을 바꾼다(명세 §3.1 "변경은 추후 프로필에서").
     * `completeOnboarding`과 같은 409 함정을 피해야 하므로 건너뛰기 조건이 여기도 있다. */
    func updateNickname(_ nickname: String) async {
        guard case .signedIn(let profile) = phase, profile.nickname != nickname else { return }
        await patchProfile(UpdateMeBody(nickname: nickname))
    }

    /* 아바타 사진(§3.4). 왕복이 **넷**이다 — 업로드 셋(`MediaUploader`) + 프로필 PATCH.
     *
     * 화면이 아니라 여기서 이어 붙이는 이유는 `CaptureFlow.commit`과 같다: 중간에 화면이
     *사라지면(탭 전환·시트 닫기) 남은 왕복이 죽은 화면의 상태에 쓰인다. 서버는 **ready이고
     * kind가 avatar인 자기 미디어**만 프로필에 붙여 주므로(`MEDIA_NOT_READY`), 셋을 끝내기
     * 전에 PATCH가 나가면 400이다.
     *
     * `UIKit`을 여기서 쓰는 대가로 그 순서를 한곳에 묶었다. */
    func uploadAvatar(_ image: UIImage) async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        failure = nil
        defer { isAuthenticating = false }

        do {
            let media = try await MediaUploader(client: client).upload(image, kind: .avatar)
            phase = .signedIn(try await client.send(
                .patch, "/users/me",
                body: UpdateMeBody(avatarMediaId: .value(media.id)), as: UserProfile.self
            ))
        } catch {
            failure = message(for: error)
        }
    }

    /// 사진 앱이 바이트를 내주지 못했다(iCloud 다운로드 실패 등). 서버에 간 적이 없으므로
    /// 서버 문구가 없고, 실패 표시는 다른 실패와 같은 자리에 있어야 한다.
    func failAvatarPreparation() {
        failure = "사진을 불러오지 못했어요. 다른 사진을 골라주세요"
    }

    /// 기본 이미지로 되돌린다. `null`을 실어야 지워지므로 `Field.null`이다 — 키를 빼면 "안 건드림"이다.
    func removeAvatar() async {
        await patchProfile(UpdateMeBody(avatarMediaId: .null))
    }

    private func patchProfile(_ body: UpdateMeBody) async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        failure = nil
        defer { isAuthenticating = false }

        do {
            phase = .signedIn(try await client.send(
                .patch, "/users/me", body: body, as: UserProfile.self
            ))
        } catch {
            failure = message(for: error)
        }
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
