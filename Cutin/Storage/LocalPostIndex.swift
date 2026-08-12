/* posts.json 읽기/쓰기. 두 가지를 고친다.
 *
 * ① **스키마 봉투** — 이전 형식은 최상위가 그냥 배열이라 레코드 모양이 바뀌면 구버전 파일을
 *    알아볼 방법이 없었다. `schemaVersion`을 씌우고, 봉투 없는 옛 파일은 v0으로 읽어 올린다.
 *
 * ② **디코드 실패 시 원본을 덮어쓰지 않는다** — 이전 구현은 `?? []`로 빈 배열을 삼킨 뒤
 *    다음 저장에서 posts.json을 빈 배열로 덮어썼다. 사용자 눈에는 포스트가 전부 사라지고
 *    JPEG만 고아로 남는다. 이제 망가진 파일은 옆으로 치우고 그 사실을 호출자에게 알린다. */

import Foundation

struct LocalPostIndex: Sendable {
    private let vault: FileVault
    private let name = "posts.json"

    init(vault: FileVault) {
        self.vault = vault
    }

    static let currentSchema = 1

    private struct Envelope: Codable {
        var schemaVersion: Int
        var posts: [ComposedPost]
    }

    enum Outcome {
        /// 정상 로드 (봉투 없는 v0에서 올라온 경우 `migrated == true`)
        case loaded([ComposedPost], migrated: Bool)
        /// 파일이 없다 — 첫 실행이거나 인덱스를 잃었다. 새로 써도 잃을 게 없다
        case absent
        /// 디코드 실패. 원본을 이 경로로 치워 뒀으므로 새로 써도 안전하다
        case quarantined(URL)
        /* 파일이 있는데 읽지 못했거나(일시적 I/O·데이터 보호 잠금) 치우지도 못했다.
         * **덮어쓰면 안 되는 상태** — 다음 실행에 성공할 수 있는 원본이 그대로 남아 있다. */
        case unwritable
    }

    func load() -> Outcome {
        guard vault.exists(name) else { return .absent }
        // 읽기 실패를 `.absent`로 뭉개면 온전한 인덱스를 자리값으로 덮어쓴다.
        guard let data = try? vault.read(name) else { return .unwritable }

        let decoder = FileVault.decoder()
        if let envelope = try? decoder.decode(Envelope.self, from: data) {
            return .loaded(envelope.posts, migrated: envelope.schemaVersion < Self.currentSchema)
        }
        // v0: 봉투 없는 최상위 배열
        if let posts = try? decoder.decode([ComposedPost].self, from: data) {
            return .loaded(posts, migrated: true)
        }
        // 치우기에 실패하면 원본이 제자리에 남는다 — 그때 새로 쓰면 지키려던 바이트가 사라진다.
        guard let quarantine = try? vault.moveAside(name, suffix: "corrupt") else {
            return .unwritable
        }
        return .quarantined(quarantine)
    }

    func save(_ posts: [ComposedPost]) throws {
        let envelope = Envelope(schemaVersion: Self.currentSchema, posts: posts)
        try vault.write(FileVault.encoder().encode(envelope), to: name)
    }
}
