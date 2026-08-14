/* 푸시 디바이스 등록 — `POST /devices` · `DELETE /devices`.
 *
 * ## ⚠️ 아직 알림이 오지 않는다
 *
 * 계약은 붙였지만 **양쪽에 남은 일이 있다**:
 *
 * 1. **앱**: Push Notifications 자격(entitlement)이 없다. 추가하려면 pbxproj를 만져야 하는데,
 *    릴리즈당 한 브랜치만 pbxproj를 건드린다는 규칙이 있어 릴리즈 준비 브랜치의 몫이다.
 *    자격이 없으면 `registerForRemoteNotifications()`가 토큰 대신 오류를 준다.
 * 2. **서버**: `PushService`가 인터페이스뿐이고 APNs 구현이 없다(`shared/push/pushService.ts`
 *    머리말에 "APNs가 확정되기 전까지 인터페이스로만 다룬다"고 적혀 있다).
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
                                     timezone: TimeZone.current.identifier),
            as: Device.self
        )
    }

    /// 로그아웃 **전에** 부른다 — 토큰이 남으면 다음 사용자에게 앞사람 알림이 간다.
    func revoke() async {
        guard let registeredToken else { return }
        try? await client.send(.delete, "/devices",
                               body: RevokeDeviceBody(pushToken: registeredToken))
        self.registeredToken = nil
    }
}
