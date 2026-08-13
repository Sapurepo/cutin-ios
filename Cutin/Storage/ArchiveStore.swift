/* 보관(북마크) — 명세 §7.4.
 *
 * 포스트 레코드에 `isArchived` 필드를 넣지 않고 **별도 파일에 id 집합**으로 둔다.
 * 0.2.0에서 보관은 서버가 소유하는 상태가 되는데(내 계정의 북마크), 그때 포스트 레코드에
 * 섞여 있으면 포스트 스키마와 보관 스키마를 한꺼번에 갈아야 한다. 파일이 갈리면 이 파일만
 * 서버 호출로 대체하면 된다.
 *
 *     Documents/archive.json   ← ["uuid", …]
 *
 * 목록 순서는 담지 않는다. 보관 탭은 포스트의 촬영 시각 순으로 보여주므로 집합으로 충분하다. */

import Foundation
import Observation

@MainActor
@Observable
final class ArchiveStore {
    private(set) var ids: Set<UUID> = []

    /* 파일이 **있는데 읽지 못한** 상태. 빈 집합으로 시작해 버리면 다음 toggle의 persist가
     * 온전한 원본을 id 하나짜리로 덮어쓴다 — 포스트 인덱스가 하드닝된 것과 정확히 같은
     * 소실 경로다(읽기 실패를 소실로 오해해 덮어쓰기). 이 상태에서는 쓰기를 전부 막는다. */
    @ObservationIgnored private var isUnreadable = false

    @ObservationIgnored private let vault = FileVault.documents()
    @ObservationIgnored private static let name = "archive.json"

    init() {
        load()
    }

    func contains(_ id: UUID) -> Bool { ids.contains(id) }

    /// 보관 여부를 뒤집고 파일에 남긴다. 실패하면 메모리도 되돌린다 —
    /// 화면에는 보관됐는데 다음 실행에 사라지는 것이 조용히 실패하는 것보다 나쁘다.
    func toggle(_ id: UUID) {
        guard !isUnreadable else { return }
        let previous = ids
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        guard persist() else {
            ids = previous
            return
        }
    }

    /// 포스트가 삭제되면 보관 기록도 의미가 없다. 남겨 두면 존재하지 않는 id가 파일에 쌓인다.
    func forget(_ id: UUID) {
        guard !isUnreadable, ids.contains(id) else { return }
        ids.remove(id)
        _ = persist()
    }

    /* "파일 없음"과 "읽기 실패"를 가른다. 없음은 첫 실행이라 빈 집합이 맞고,
     * 실패(잠긴 디스크·중간에 끊긴 쓰기)는 원본이 남아 있으므로 덮어쓰면 안 된다. */
    private func load() {
        guard vault.exists(Self.name) else { return }
        guard let data = try? vault.read(Self.name),
              let stored = try? FileVault.decoder().decode([UUID].self, from: data)
        else {
            isUnreadable = true
            return
        }
        ids = Set(stored)
    }

    private func persist() -> Bool {
        guard let data = try? FileVault.encoder().encode(Array(ids)) else { return false }
        return (try? vault.write(data, to: Self.name)) != nil
    }
}
