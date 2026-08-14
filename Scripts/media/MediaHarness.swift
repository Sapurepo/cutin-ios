/* 임시 검증 하니스 — 커밋 전에 삭제한다.
 *
 * 업로드는 왕복 셋이고 순서가 전부다:
 *
 *   ① `POST /media/uploads`       목적지 발급 (pending 미디어가 생긴다)
 *   ② `PUT  {url}`                바이트 전송 — **`[auth]`라 Bearer가 필요하다**
 *   ③ `POST /media/{id}/complete` 크기를 알려 ready로 만든다
 *
 * 틀렸을 때의 증상이 조용하다: ③을 빠뜨리면 미디어가 pending으로 남고, 서버는 pending을
 * 포스트·프로필에 붙이지 못하게 막는다(`MEDIA_NOT_READY`). 화면에서는 "올라갔는데 안 붙는다"다.
 *
 * 스텁도 실제 서버처럼 상태 기계다 — 바이트 없이 complete하면 거절하고, ready가 아닌 미디어를
 * 프로필에 붙이면 400을 낸다. 관대한 스텁으로는 순서를 시험할 수 없다.
 *
 * 실행: mediastub.py를 띄우고 SIMCTL_CHILD_MEDIA_CHECK=1 로 앱을 띄운다.
 * **서명해서 빌드해야 한다** — `restore()`가 Keychain을 읽는다. */

#if DEBUG
import UIKit

@MainActor
enum MediaHarness {
    static var isRequested: Bool {
        ProcessInfo.processInfo.environment["MEDIA_CHECK"] == "1"
    }

    private static let stub = URL(string: "http://127.0.0.1:8768")!
    private static var failures = 0

    static func run() async {
        await scenarioUploadOrder()
        await scenarioPixelSize()
        await scenarioAvatarEndToEnd()
        await scenarioRefreshDuringUpload()
        await scenarioRemoveAvatar()
        await scenarioDownsample()

        TokenStore().clear()
        print("=== 결과: \(failures == 0 ? "전부 통과" : "실패 \(failures)건") ===")
        fflush(stdout)
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - ① 세 왕복의 순서

    private static func scenarioUploadOrder() async {
        print("=== ① 업로드 세 왕복 ===")
        await reset()
        let client = APIClient(baseURL: stub)
        await client.setAccessToken("GOOD")

        do {
            let media = try await MediaUploader(client: client).upload(solid(80, 60), kind: .cut)
            let counts = await state()
            check("① uploads 1회", counts["createCount"] as? Int == 1)
            check("② PUT 1회", counts["putCount"] as? Int == 1)
            check("③ complete 1회", counts["completeCount"] as? Int == 1)
            // 스텁이 바이트 없는 complete를 거절하므로, 통과 자체가 순서의 증거다.
            check("kind를 그대로 실었다", counts["lastKind"] as? String == "cut")
            check("mime을 그대로 실었다", counts["lastMime"] as? String == "image/jpeg")
            /* 서버가 준 헤더를 그대로 실어야 한다. Content-Type을 앱이 지어내면
             * 스토리지가 바뀌었을 때(서명 헤더가 함께 오는 경우) 조용히 깨진다. */
            check("서버가 준 Content-Type을 실었다",
                  counts["lastContentType"] as? String == "image/jpeg")
            // PUT은 [auth]다. 목적지 헤더만 싣고 인증을 빠뜨리면 401이다.
            check("PUT에 Bearer를 붙였다", counts["lastAuthorized"] as? Bool == true)
            check("바이트가 실제로 갔다", (counts["lastBytes"] as? Int ?? 0) > 0)
            check("ready 미디어를 돌려받았다", media.width == 80 && media.height == 60)
        } catch {
            failures += 1
            print("FAIL  업로드가 던졌다: \(error)")
        }
    }

    // MARK: - ② complete에 싣는 크기

    private static func scenarioPixelSize() async {
        print("=== ② complete의 width·height는 실제 픽셀 ===")
        await reset()
        let client = APIClient(baseURL: stub)
        await client.setAccessToken("GOOD")

        /* `UIImage.size`는 포인트라 scale이 1이 아니면 바이트의 픽셀 수와 다르다.
         * 서버는 이 값을 그대로 믿으므로, 포인트를 보내면 상세 화면의 비율이 어긋난다. */
        let scaled = UIImage(cgImage: solid(120, 90).cgImage!, scale: 3, orientation: .up)
        check("표본이 포인트와 픽셀이 다르다", scaled.size.width == 40 && scaled.pixelSize.width == 120)

        _ = try? await MediaUploader(client: client).upload(scaled, kind: .avatar)
        let counts = await state()
        check("픽셀 크기를 보냈다(포인트가 아니다)",
              counts["lastWidth"] as? Int == 120 && counts["lastHeight"] as? Int == 90)
    }

    // MARK: - ③ 아바타 — 업로드부터 프로필까지

    private static func scenarioAvatarEndToEnd() async {
        print("=== ③ 아바타 업로드 → 프로필 반영 ===")
        await reset()
        let session = await signedInSession()

        await session.uploadAvatar(solid(200, 200))

        let counts = await state()
        check("업로드 세 왕복", counts["createCount"] as? Int == 1
              && counts["putCount"] as? Int == 1 && counts["completeCount"] as? Int == 1)
        check("kind가 avatar", counts["lastKind"] as? String == "avatar")
        check("프로필 PATCH 1회", counts["patchCount"] as? Int == 1)
        check("실패 없음", session.failure == nil)
        /* 스텁이 ready가 아닌 미디어를 400으로 막으므로, avatarUrl이 생겼다는 것은
         * complete가 PATCH보다 **먼저** 갔다는 증거다. */
        check("프로필에 사진이 붙었다", {
            if case .signedIn(let profile) = session.phase { return profile.avatarUrl != nil }
            return false
        }())
    }

    // MARK: - ④ 업로드 중 토큰 만료

    private static func scenarioRefreshDuringUpload() async {
        print("=== ④ PUT이 401 → 재발급 → 재시도 ===")
        // 컷을 여러 장 올리는 동안 액세스 토큰이 만료되는 것은 흔한 일이다.
        await reset(["putUnauthorizedOnce": true])
        let session = await signedInSession()

        await session.uploadAvatar(solid(64, 64))

        let counts = await state()
        check("재발급 1회", counts["refreshCount"] as? Int == 1)
        check("PUT 2회 (401 후 재시도)", counts["putCount"] as? Int == 2)
        check("업로드가 끝까지 갔다", counts["completeCount"] as? Int == 1)
        check("실패 없음", session.failure == nil)
    }

    // MARK: - ⑤ 사진 지우기

    private static func scenarioRemoveAvatar() async {
        print("=== ⑤ 사진 지우기 — null을 실어야 지워진다 ===")
        await reset()
        let session = await signedInSession()
        await session.uploadAvatar(solid(64, 64))

        await session.removeAvatar()
        check("프로필에서 사진이 빠졌다", {
            if case .signedIn(let profile) = session.phase { return profile.avatarUrl == nil }
            return false
        }())
        check("실패 없음", session.failure == nil)
    }

    // MARK: - ⑥ 줄여서 올리기

    private static func scenarioDownsample() async {
        print("=== ⑥ 사진 앱 바이트를 줄여서 디코드 ===")
        let big = solid(2000, 1500)
        guard let data = big.jpegData(compressionQuality: 0.9) else {
            failures += 1
            print("FAIL  표본 인코딩 실패")
            return
        }
        guard let small = UIImage.downsampled(from: data, maxPixel: 512) else {
            failures += 1
            print("FAIL  다운샘플이 nil")
            return
        }
        check("긴 변이 상한 이하", max(small.pixelSize.width, small.pixelSize.height) <= 512)
        // 비율이 유지돼야 원형으로 잘랐을 때 찌그러지지 않는다.
        let ratio = Double(small.pixelSize.width) / Double(small.pixelSize.height)
        check("가로세로 비율 유지", abs(ratio - 2000.0 / 1500.0) < 0.02)
        check("망가진 바이트는 nil", UIImage.downsampled(from: Data("not an image".utf8),
                                                     maxPixel: 512) == nil)
    }

    // MARK: - 보조

    private static func solid(_ width: Int, _ height: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
            .image { _ in
                UIColor.systemTeal.setFill()
                UIRectFill(CGRect(x: 0, y: 0, width: width, height: height))
            }
    }

    private static func signedInSession() async -> AuthSession {
        TokenStore().save(AuthTokens(accessToken: "GOOD", refreshToken: "R1",
                                     expiresAt: Date().addingTimeInterval(3600)))
        let session = AuthSession(client: APIClient(baseURL: stub))
        await session.restore()
        return session
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
