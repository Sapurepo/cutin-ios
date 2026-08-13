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

/// 인덱스를 어떤 상태로 읽었는지. 화면이 사용자에게 설명할 근거이자, 쓰기를 막을 근거다.
enum IndexStatus {
    case ok
    /// 인덱스를 잃어 사진에서 되살렸다. 캡션·보정은 복구되지 않는다.
    /// `quarantine`이 있으면 손상된 원본을 그 경로에 보존했다는 뜻.
    case recovered(count: Int, quarantine: URL?)
    /// 인덱스 파일이 있는데 읽지 못했다 — 덮어쓰지 않고 쓰기를 막는다.
    case unwritable
}

enum FeedStoreError: Error {
    /// 목록을 읽을 수 없는 상태에서 쓰기를 시도했다. 쓰면 원본 인덱스를 잃는다.
    case indexUnwritable
}

@MainActor
@Observable
final class FeedStore {
    private(set) var posts: [ComposedPost] = []
    private(set) var indexStatus: IndexStatus = .ok

    private let files: PostFileStore
    private let index: LocalPostIndex
    private let cache = ImageCache()

    init() {
        files = PostFileStore(vault: FileVault(directory: "Posts"))
        index = LocalPostIndex(vault: .documents())
        load()
    }

    // MARK: - 읽기

    /// Route가 모델이 아니라 id를 나르므로(규칙 4) 상세 화면이 여기서 되찾는다.
    func post(id: UUID) -> ComposedPost? {
        posts.first { $0.id == id }
    }

    /// 공유·사진 앱 저장이 쓰는 원본 파일 경로. 이미지를 다시 인코딩하지 않고 그대로 넘긴다.
    func imageURL(for post: ComposedPost) -> URL {
        files.url(post.imageFilename)
    }

    /// `maxPixel`은 긴 변 기준 상한 — 호출부가 표시 크기를 알고 넘긴다.
    func image(for post: ComposedPost, maxPixel: CGFloat) async -> UIImage? {
        let name = post.imageFilename
        if let cached = cache.image(name, maxPixel: maxPixel) { return cached }

        let files = self.files
        let decoded = await Task.detached(priority: .userInitiated) {
            files.decode(name, maxPixel: maxPixel)
        }.value

        // 셀이 화면을 벗어나며 취소된 뒤라면 캐시를 채우지 않는다. CGImageSource 디코드 자체는
        // 중간에 끊을 수 없어 이미 끝난 작업이고, 여기서 막는 건 뒤이은 상태 갱신뿐이다.
        guard !Task.isCancelled else { return nil }

        if let decoded {
            cache.store(decoded, for: name, maxPixel: maxPixel)
        }
        return decoded
    }

    // MARK: - 쓰기

    /// 합성 결과를 저장하고 피드 맨 앞에 붙인다.
    func save(
        image: UIImage,
        template: Template?,
        frame: Frame?,
        filterID: FilterID,
        caption: String
    ) throws {
        try requireWritableIndex()

        let id = UUID()
        let name = files.filename(for: id)
        try files.write(image, to: name)

        let post = ComposedPost(
            id: id,
            createdAt: Date(),
            imageFilename: name,
            template: template,
            frame: frame,
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
    }

    func delete(_ post: ComposedPost) throws {
        try requireWritableIndex()

        let remaining = posts.filter { $0.id != post.id }
        // 인덱스를 먼저 쓴다. 여기서 죽으면 파일이 고아로 남을 뿐 목록은 온전하다.
        // 반대 순서면 파일은 없는데 목록에는 남아 빈 카드가 생긴다.
        try index.save(remaining)
        posts = remaining
        try? files.remove(post.imageFilename)
        cache.remove(post.imageFilename)
    }

    /// 복구 안내를 사용자가 확인했다. 쓰기 금지 상태(`unwritable`)는 사용자가 닫을 수 있는 게 아니다.
    func acknowledgeRecovery() {
        if case .recovered = indexStatus { indexStatus = .ok }
    }

    private func requireWritableIndex() throws {
        if case .unwritable = indexStatus { throw FeedStoreError.indexUnwritable }
    }

    // MARK: - 영속화

    private func load() {
        switch index.load() {
        case .loaded(let stored, let migrated):
            posts = stored.sorted { $0.createdAt > $1.createdAt }
            // 봉투 없는 옛 형식이었으면 현재 스키마로 다시 써 둔다.
            if migrated { try? index.save(posts) }

        /* 구버전 스키마라 의도적으로 버렸다(0.2.0 결정: 로컬 포스트 폐기).
         *
         * **JPEG에서 되살리지 않는다.** 되살리면 메타 없는 자리값 레코드가 목록을 채우고,
         * 사용자는 "버렸다"는 결정 대신 "깨졌다"를 보게 된다. 인덱스만 새로 쓰고 빈 목록으로
         * 시작한다 — 파일은 남아 있으므로 나중에 필요하면 손으로 꺼낼 수 있다. */
        case .discarded(let from):
            print("[FeedStore] 인덱스 스키마 v\(from) → v\(LocalPostIndex.currentSchema): 옛 레코드를 버립니다")
            posts = []
            try? index.save(posts)

        /* 손상된 원본은 이미 격리됐다 — 되살린 게 0장이어도 상태를 알린다.
         * 조용히 빈 피드를 보여주면 사용자는 목록이 사라진 이유를 알 방법이 없다. */
        case .quarantined(let url):
            posts = rebuildFromFiles()
            indexStatus = .recovered(count: posts.count, quarantine: url)
            try? index.save(posts)

        /* 파일이 없다 — 첫 실행이면 사진도 없어서 복구가 빈 목록을 낸다.
         * 사진이 있는데 인덱스만 없다면 인덱스를 잃은 것이다: 전부 삭제한 경우라면
         * `delete()`가 빈 목록을 **쓰기** 때문에 파일이 사라지지는 않는다. 그래서 여기서
         * 사진을 주워도 삭제한 포스트가 되살아나지 않는다. */
        case .absent:
            posts = rebuildFromFiles()
            guard !posts.isEmpty else { return }
            indexStatus = .recovered(count: posts.count, quarantine: nil)
            try? index.save(posts)

        // 읽지 못한 원본이 제자리에 있다. 목록은 못 보여주지만 덮어쓰지도 않는다.
        case .unwritable:
            posts = []
            indexStatus = .unwritable
        }
    }

    /* 인덱스를 잃었을 때 JPEG에서 목록을 되살린다. 사진은 사용자가 유일하게 잃으면 안 되는
     * 것이라 "빈 목록으로 시작"보다 이게 맞다.
     *
     * 캡션·보정·템플릿·프레임은 인덱스에만 있던 메타데이터라 복구되지 않는다. 없는 것은
     * nil로 두고, 진짜 값으로 오해되지 않도록 `recoveredFromFile`로 표시해 파일에 남긴다. */
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
                    /* 0.1.0은 여기에 `.four`·`.grid2x2` 자리값을 넣었다. 이제는 nil이다 —
                     * 모르는 값을 아는 척하면 프로필 통계가 거짓이 된다. */
                    template: nil,
                    frame: nil,
                    filterID: .original,
                    caption: "",
                    recoveredFromFile: true
                )
            }
            .sorted { $0.createdAt > $1.createdAt }
    }
}
