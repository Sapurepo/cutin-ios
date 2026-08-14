/* APNs 토큰을 받기 위한 최소 델리게이트.
 *
 * SwiftUI에는 `didRegisterForRemoteNotificationsWithDeviceToken`에 대응하는 훅이 없다.
 * UIKit 델리게이트를 붙이는 것 말고는 토큰을 받을 길이 없어서 이 파일 하나를 둔다 —
 * **다른 일은 시키지 않는다.** 생애주기 처리는 여전히 `RootView`의 `scenePhase`가 한다.
 *
 * 등록기를 static으로 넘기는 이유: `@UIApplicationDelegateAdaptor`가 만드는 인스턴스에
 * 값을 주입할 자리가 없다. 앱이 하나뿐이라 인스턴스도 하나다. */

import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    /// `CutinApp.init`이 심는다. 델리게이트가 만들어지는 시점과 무관하게 값이 있어야 한다.
    @MainActor static var registrar: PushRegistrar?

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            await Self.registrar?.submit(token: deviceToken)
        }
    }

    /* 등록 실패. **자격(entitlement)이 없으면 여기로 온다** — 지금이 그 상태다
     * (`PushRegistrar` 머리말 참조). 사용자가 할 수 있는 일이 없어 화면에 띄우지 않고,
     * 원인을 쫓을 수 있게 로그만 남긴다. */
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: any Error
    ) {
        print("[Push] APNs 등록 실패: \(error)")
    }
}
