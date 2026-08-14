/* 카카오 로그인 — SDK를 감싸 **액세스 토큰 문자열 하나**만 내놓는다.
 *
 * 서버가 필요한 것은 그 문자열뿐이다(`POST /auth/oauth/kakao`의 `token`). SDK 타입(`OAuthToken`)이
 * 이 파일 밖으로 새면 카카오를 걷어낼 때 세션·화면까지 따라 고쳐야 한다.
 *
 * **provider마다 서버가 기대하는 토큰이 다르다.** 서버 `oauthVerifier.ts`는 kakao를
 * `kapi.kakao.com/v2/user/me`의 Bearer로 쓰므로 **액세스 토큰**이 맞다.
 * (google은 `id_token`을 JWKS로 검증한다 — 0.2.0에서 구글은 도입하지 않는다.)
 *
 * 앱 전환 로그인(`loginWithKakaoTalk`)을 먼저 시도하고, 카카오톡이 없으면 웹 로그인으로 내려간다.
 * 시뮬레이터에는 카카오톡이 없으므로 항상 웹 경로를 탄다. */

import Foundation
import KakaoSDKAuth
import KakaoSDKCommon
import KakaoSDKUser

@MainActor
enum KakaoLogin {
    /// `Info.plist`의 앱 키로 SDK를 초기화한다. 앱 시작 시 한 번.
    static func initialize() {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "KAKAO_APP_KEY") as? String,
              !key.isEmpty
        else {
            preconditionFailure(
                "KAKAO_APP_KEY가 비어 있습니다. Config/Shared.xcconfig의 CUTIN_KAKAO_APP_KEY를 확인하세요."
            )
        }
        KakaoSDK.initSDK(appKey: key)
    }

    /* 카카오톡 앱이 되돌려 보내는 URL을 SDK에 넘긴다. 이 처리가 없으면 앱 전환 로그인이
     * 카카오톡에서 돌아온 뒤 아무 일도 일어나지 않고 멈춘다. */
    static func handle(_ url: URL) -> Bool {
        guard AuthApi.isKakaoTalkLoginUrl(url) else { return false }
        return AuthController.handleOpenUrl(url: url)
    }

    /// 로그인해서 카카오 액세스 토큰을 얻는다.
    static func accessToken() async throws -> String {
        if UserApi.isKakaoTalkLoginAvailable() {
            do {
                return try await withTalk()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                /* 카카오톡이 깔려 있어도 실패할 수 있다(로그인 안 된 카카오톡, 구버전).
                 * 여기서 멈추면 사용자는 다른 수단이 없다 — 웹으로 내려간다. */
                return try await withAccount()
            }
        }
        return try await withAccount()
    }

    private static func withTalk() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            UserApi.shared.loginWithKakaoTalk { token, error in
                continuation.resume(with: Self.result(token?.accessToken, error))
            }
        }
    }

    private static func withAccount() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            UserApi.shared.loginWithKakaoAccount { token, error in
                continuation.resume(with: Self.result(token?.accessToken, error))
            }
        }
    }

    /* SDK 타입을 여기서 끊는다 — continuation에 실어 보내는 값은 `String`뿐이다.
     * `OAuthToken`은 Sendable이 아니라 격리 경계를 넘길 수 없고, 넘길 필요도 없다. */
    private static func result(_ token: String?, _ error: (any Error)?) -> Result<String, any Error> {
        if let token { return .success(token) }
        if let error {
            // 사용자가 로그인 창을 닫은 것은 실패가 아니다 — 화면에 오류를 띄우지 않도록 구분한다.
            if let sdkError = error as? SdkError, sdkError.isClientFailed,
               case .Cancelled = sdkError.getClientError().reason {
                return .failure(CancellationError())
            }
            return .failure(error)
        }
        return .failure(LoginFailure.emptyToken)
    }

    enum LoginFailure: Error {
        /// SDK가 토큰도 오류도 주지 않은 경우. 계약상 있을 수 없지만 옵셔널 둘이라 표현은 가능하다.
        case emptyToken
    }
}
