/* 푸시 디바이스 등록 — `POST /devices` · `DELETE /devices`.
 *
 * ## ⚠️ 아직 알림이 오지 않는다
 *
 * 서버는 준비됐다 — APNs 발송 구현(`shared/push/apnsPushService.ts`)이 있고, 자격증명
 * 4종(env)을 채우면 실제로 보낸다. 남은 것은 **앱의 Push Notifications 자격(entitlement)**
 * 하나다. 추가하려면 pbxproj를 만져야 하는데, 릴리즈당 한 브랜치만 pbxproj를 건드린다는
 * 규칙이 있어 릴리즈 준비 브랜치의 몫이다. 자격이 없으면
 * `registerForRemoteNotifications()`가 토큰 대신 오류를 준다.
 *
 * 그래서 이 파일은 **토큰을 받으면 서버에 넣는 경로**를 완성해 두고, 실패는 조용히 삼킨다.
 * 알림이 오지 않는 것은 사용자가 고칠 수 있는 문제가 아니고, 자격이 붙는 순간 그대로 동작한다.
 *
 * ## 로그아웃에서 토큰을 지우는 이유
 *
 * 한 기기를 두 사람이 쓰면(계정 전환) 앞사람의 알림이 뒷사람에게 간다. `DELETE /devices`가
 * 그 연결을 끊는다. 서버는 토큰으로 지우므로 로그아웃 **전에** 불러야 한다. */

import UIKit
import UserNotifications

@MainActor
@Observable
final class PushRegistrar: NSObject {
    /// 사용자가 알림을 허용했는지. 설정 화면이 이 값으로 안내를 가른다.
    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    /// 마지막으로 서버에 넣은 토큰. 로그아웃 때 이 값으로 지운다.
    private(set) var registeredToken: String?

    @ObservationIgnored private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func refreshAuthorization() async {
        authorization = await UNUserNotificationCenter.current().notificationSettings()
            .authorizationStatus
    }

    /* 권한을 묻고 허용되면 APNs에 등록한다. 토큰은 앱 델리게이트가 받아 `submit(token:)`으로
     * 넘긴다 — UIKit이 콜백으로만 주는 값이라 `async`로 감쌀 자리가 없다.
     *
     * **거부는 실패가 아니다.** 사용자가 안 받겠다고 한 것이므로 오류 문구를 띄우지 않는다. */
    func requestAuthorization() async {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        await refreshAuthorization()
        guard granted else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// 이미 허용한 사용자를 위해 앱을 켤 때마다 등록한다 — 토큰은 재설치·복원에서 바뀐다.
    func registerIfAuthorized() async {
        await refreshAuthorization()
        guard authorization == .authorized || authorization == .provisional else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    /* APNs 토큰을 서버에 넣는다. 실패를 삼키는 이유: 사용자가 할 수 있는 일이 없고, 다음 실행에
     * 다시 등록한다. 서버도 같은 토큰을 두 번 받으면 갱신으로 처리한다. */
    func submit(token: Data) async {
        let hex = token.map { String(format: "%02x", $0) }.joined()
        registeredToken = hex
        _ = try? await client.send(
            .post, "/devices",
            body: RegisterDeviceBody(platform: "ios", pushToken: hex,
                                     pushEnvironment: Self.pushEnvironment,
                                     timezone: TimeZone.current.identifier),
            as: Device.self
        )
    }

    /* 이 토큰이 어느 APNs 엔드포인트에 유효한지. 서버가 필수로 요구한다 — 틀리면
     * `BadDeviceToken`으로 전부 실패하는데 원인이 서버 로그에만 남는다.
     *
     * 프로비저닝 프로파일의 `aps-environment`가 판정 기준이다: `development`면 sandbox,
     * 그 외는 production. **프로파일이 없으면 production** — App Store 설치본은 프로파일이
     * 벗겨져 나오고, 그 빌드의 토큰은 production이다. TestFlight 빌드는 프로파일이 있지만
     * 값이 `production`이라 같은 결론에 닿는다. 시뮬레이터는 프로파일 없이 sandbox 토큰을
     * 받으므로 먼저 가른다.
     *
     * 프로파일은 CMS 서명으로 감싼 plist인데 XML이 바이트 그대로 들어 있어, 키를 찾고
     * 바로 뒤의 값만 읽는다 — 서명을 푸는 것보다 깨질 자리가 적다. */
    static let pushEnvironment: String = {
        #if targetEnvironment(simulator)
        return "sandbox"
        #else
        guard let url = Bundle.main.url(forResource: "embedded",
                                        withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let key = data.range(of: Data("<key>aps-environment</key>".utf8))
        else { return "production" }
        let tail = data.subdata(in: key.upperBound
            ..< min(key.upperBound + 64, data.endIndex))
        return String(decoding: tail, as: UTF8.self).contains("development")
            ? "sandbox" : "production"
        #endif
    }()

    /// 로그아웃 **전에** 부른다 — 토큰이 남으면 다음 사용자에게 앞사람 알림이 간다.
    func revoke() async {
        guard let registeredToken else { return }
        try? await client.send(.delete, "/devices",
                               body: RevokeDeviceBody(pushToken: registeredToken))
        self.registeredToken = nil
    }
}
