/* 토큰 보관 — Keychain.
 *
 * `UserDefaults`가 아닌 이유: 리프레시 토큰은 **비밀번호와 같은 값**이다. 그것 하나로 액세스
 * 토큰을 계속 새로 받을 수 있으므로 계정 탈취와 같다. UserDefaults의 plist는 기기 백업에
 * 평문으로 들어가고 탈옥 기기에서 그대로 읽힌다.
 *
 * `kSecAttrAccessibleAfterFirstUnlock`을 쓴다 — `WhenUnlocked`면 화면이 잠긴 동안 갱신이
 * 실패하고(백그라운드 새로고침·푸시 처리), `Always`는 잠금과 무관해 보호가 없다.
 *
 * 실패를 던지지 않고 Bool·옵셔널로 돌린다. 호출부가 Keychain 오류 코드로 할 수 있는 일이
 * 없다 — 읽히면 쓰고, 안 읽히면 로그인 화면으로 보내는 것뿐이다. */

import Foundation
import Security

struct AuthTokens: Sendable, Equatable {
    var accessToken: String
    var refreshToken: String
    /// 액세스 토큰이 만료되는 시점. 서버가 준 `expiresIn`(초)에서 만든다.
    var expiresAt: Date

    /* 만료 직전을 만료로 본다. 요청이 날아가는 동안 만료되면 401을 맞고 재발급·재시도로
     * 한 바퀴 더 도는데, 미리 갱신하면 그 왕복이 없다. */
    func isExpired(now: Date = .now, leeway: TimeInterval = 60) -> Bool {
        now.addingTimeInterval(leeway) >= expiresAt
    }
}

struct TokenStore: Sendable {
    /// 계정 하나만 보관한다 — 다중 계정은 명세에 없다.
    private let service = "com.sapurepo.cutin.tokens"
    private let account = "session"

    func load() -> AuthTokens? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let stored = try? JSONDecoder().decode(Stored.self, from: data)
        else { return nil }

        return AuthTokens(
            accessToken: stored.accessToken,
            refreshToken: stored.refreshToken,
            expiresAt: stored.expiresAt
        )
    }

    /* 있으면 갱신, 없으면 추가. `SecItemAdd`만 쓰면 두 번째 로그인이 `errSecDuplicateItem`으로
     * 실패해 **옛 토큰이 남는다** — 계정을 바꿔 로그인했는데 이전 계정으로 붙는 경로다. */
    @discardableResult
    func save(_ tokens: AuthTokens) -> Bool {
        guard let data = try? JSONEncoder().encode(Stored(tokens)) else { return false }

        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }

        var insert = baseQuery
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    /// 로그아웃. 항목이 없어도 성공으로 본다 — 없는 것이 목표 상태다.
    @discardableResult
    func clear() -> Bool {
        let status = SecItemDelete(baseQuery as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// Keychain에는 한 덩어리로 넣는다 — 액세스·리프레시가 따로 저장되면 둘이 어긋난 상태가 생긴다.
    private struct Stored: Codable {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Date

        init(_ tokens: AuthTokens) {
            accessToken = tokens.accessToken
            refreshToken = tokens.refreshToken
            expiresAt = tokens.expiresAt
        }
    }
}
