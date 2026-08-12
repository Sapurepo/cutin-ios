/* 합성 결과 로컬 저장 — 백엔드가 아직 없으므로 Documents에 JPEG + JSON 인덱스로 둔다.
 * 파일 접근 규칙은 Storage/ 로 내려가고 여기는 목록 상태와 정책만 남는다.
 *
 * 이전 구현에서 고친 것 셋:
 * ① 뷰 본문에서 1080px JPEG을 통째로 디코드하던 것 → 다운샘플 + 메인 액터 밖 + 캐시
 * ② 인덱스 디코드 실패를 `?? []`로 삼킨 뒤 다음 저장에서 빈 배열로 덮어써 인덱스를 영구
 *    파괴하던 것 → 망가진 파일은 격리하고 JPEG에서 목록을 복구
 * ③ 저장 실패를 nil 반환으로 알려 호출부가 그냥 무시하던 것 → throw */

import Observation
import UIKit

/// 인덱스를 잃고 파일에서 되살렸다는 기록. 사용자에게 "무엇이 복구되지 않았는지" 알리는 근거.
struct IndexRecovery {
    let recovered: Int
    let quarantine: URL?
}

@MainActor
@Observable
final class FeedStore {
    private(set) var posts: [ComposedPost] = []
    private(set) var recovery: IndexRecovery?

    private let files: PostFileStore
    private let index: LocalPostIndex
    private let cache = ImageCache()

    init() {
        files = PostFileStore(vault: FileVault(directory: "Posts"))
        index = LocalPostIndex(vault: .documents())
        load()
    }

    // MARK: - 읽기

    /// `maxPixel`은 긴 변 기준 상한 — 호출부가 표시 크기를 알고 넘긴다.
    func image(for post: ComposedPost, maxPixel: CGFloat) async -> UIImage? {
        let name = post.imageFilename
        if let cached = cache.image(name, maxPixel: maxPixel) { return cached }

        let files = self.files
        let decoded = await Task.detached(priority: .userInitiated) {
            files.decode(name, maxPixel: maxPixel)
        }.value

        if let decoded {
            cache.store(decoded, for: name, maxPixel: maxPixel)
        }
        return decoded
    }

    // MARK: - 쓰기

    /// 합성 결과를 저장하고 피드 맨 앞에 붙인다.
    @discardableResult
    func save(
        image: UIImage,
        count: CutCount,
        layout: CutLayout,
        frameID: String?,
        filterID: FilterID,
        caption: String
    ) throws -> ComposedPost {
        let id = UUID()
        let name = files.filename(for: id)
        try files.write(image, to: name)

        let post = ComposedPost(
            id: id,
            createdAt: Date(),
            imageFilename: name,
            count: count,
            layout: layout,
            frameID: frameID,
            filterID: filterID,
            caption: caption
        )

        let updated = [post] + posts
        do {
            try index.save(updated)
        } catch {
            // 인덱스에 못 올렸으면 방금 쓴 파일도 되돌린다 — 메모리·디스크·인덱스가 갈라지지 않게.
            try? files.remove(name)
            throw error
        }
        posts = updated
        return post
    }

    func delete(_ post: ComposedPost) throws {
        let remaining = posts.filter { $0.id != post.id }
        // 인덱스를 먼저 쓴다. 여기서 죽으면 파일이 고아로 남을 뿐 목록은 온전하다.
        // 반대 순서면 파일은 없는데 목록에는 남아 빈 카드가 생긴다.
        try index.save(remaining)
        posts = remaining
        try? files.remove(post.imageFilename)
    }

    // MARK: - 영속화

    private func load() {
        switch index.load() {
        case .loaded(let stored, let migrated):
            posts = stored.sorted { $0.createdAt > $1.createdAt }
            // 봉투 없는 옛 형식이었으면 현재 스키마로 다시 써 둔다.
            if migrated { try? index.save(posts) }

        case .corrupt(let quarantine):
            recover(quarantine: quarantine)

        /* 파일이 없다 — 첫 실행이면 사진도 없어서 복구가 빈 목록을 낸다.
         * 사진이 있는데 인덱스만 없다면 인덱스를 잃은 것이다: 전부 삭제한 경우라면
         * `delete()`가 빈 목록을 **쓰기** 때문에 파일이 사라지지는 않는다. 그래서 여기서
         * 사진을 주워도 삭제한 포스트가 되살아나지 않는다. */
        case .absent:
            recover(quarantine: nil)
        }
    }

    private func recover(quarantine: URL?) {
        let rebuilt = rebuildFromFiles()
        posts = rebuilt
        guard !rebuilt.isEmpty else { return }

        recovery = IndexRecovery(recovered: rebuilt.count, quarantine: quarantine)
        try? index.save(rebuilt)
    }

    /* 인덱스를 잃었을 때 JPEG에서 목록을 되살린다. 사진은 사용자가 유일하게 잃으면 안 되는
     * 것이라 "빈 목록으로 시작"보다 이게 맞다.
     *
     * 캡션·보정·레이아웃·컷 수는 인덱스에만 있던 메타데이터라 복구되지 않는다 — 아래 값들은
     * 복구 불가를 뜻하는 자리값이고, 화면에 렌더되는 것은 보정 뱃지(.original이면 숨김)뿐이다. */
    private func rebuildFromFiles() -> [ComposedPost] {
        guard let names = try? files.storedNames() else { return [] }
        let suffix = ".\(PostFileStore.fileExtension)"

        return names
            .compactMap { name -> ComposedPost? in
                guard let id = UUID(uuidString: String(name.dropLast(suffix.count))) else {
                    return nil
                }
                return ComposedPost(
                    id: id,
                    createdAt: files.creationDate(name) ?? Date(),
                    imageFilename: name,
                    count: .four,
                    layout: .grid2x2,
                    frameID: nil,
                    filterID: .original,
                    caption: ""
                )
            }
            .sorted { $0.createdAt > $1.createdAt }
    }
}
