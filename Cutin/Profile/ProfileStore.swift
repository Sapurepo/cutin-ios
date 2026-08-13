/* 프로필 — 명세 §8.1의 로컬 범위(닉네임).
 *
 * UserDefaults에 둔다. 0.2.0에서 서버 프로필이 생기면 이 값이 온보딩 닉네임(§3.1)의 시드가
 * 된다 — 파일 store를 만들 만큼의 구조가 아니고, 잃어도 사진과 달리 다시 입력하면 그만이다. */

import Foundation
import Observation

@MainActor
@Observable
final class ProfileStore {
    private static let key = "profile.nickname"

    var nickname: String {
        didSet { UserDefaults.standard.set(nickname, forKey: Self.key) }
    }

    init() {
        nickname = UserDefaults.standard.string(forKey: Self.key) ?? ""
    }

    /// 아바타 이니셜 — 닉네임의 첫 글자. 사진 아바타는 읽기 권한 키가 추가로 필요해 0.2.0.
    var initial: String {
        nickname.first.map(String.init) ?? "C"
    }
}
