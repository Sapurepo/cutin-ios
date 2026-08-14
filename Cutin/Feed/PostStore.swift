/* 서버 포스트 — 0.1.0의 `FeedStore`(로컬 posts.json + JPEG)를 대체한다.
 *
 * 한 객체가 피드·상세·보관·프로필 그리드를 함께 갖는 이유는 **같은 포스트가 네 화면에 동시에
 * 있기 때문**이다. 상세에서 보관을 누르면 피드 카드의 표시도, 보관 탭의 목록도 따라가야 한다.
 * 화면마다 목록을 따로 들면 그 동기화를 화면 수만큼 반복하게 된다.
 *
 * ## 목록은 id 배열, 포스트는 사전에
 *
 * `feed`·`bookmarks`·`userLists`는 **id 배열**이고 실제 포스트는 `posts` 사전에 한 벌만 둔다.
 * 목록마다 값을 복사해 두면 보관 토글이 세 곳을 각각 고쳐야 하고, 하나라도 빠뜨리면 같은
 * 포스트가 화면마다 다른 말을 한다.
 *
 * ## 커서 페이징
 *
 * 서버가 모든 목록에 같은 봉투를 씌운다(`{items, nextCursor}`). `nextCursor`가 null이면 끝이다.
 * **오프셋이 아니라 커서**라 페이지를 받는 사이에 새 포스트가 들어와도 항목이 밀리지 않는다.
 *
 * 캐시를 파일로 두지 않는다. 0.1.0의 로컬 인덱스는 그 자체가 원본이었지만 지금은 사본이고,
 * 사본을 두면 "서버에서 지운 포스트가 기기에 남는다"를 새로 얻는다. 오프라인 피드는 범위 밖이다. */

import Foundation
import Observation

@MainActor
@Observable
final class PostStore {
    /// 목록별 상태. 세 목록이 각자 커서와 로딩 상태를 갖는다.
    struct List {
        var ids: [UUID] = []
        var nextCursor: String?
        var isLoading = false
        /// 한 번이라도 받아 봤는지. 빈 목록과 "아직 안 받음"을 가르는 데 쓴다.
        var hasLoaded = false
        var failure: String?

        var canLoadMore: Bool { nextCursor != nil && !isLoading }

        /* 다음에 열 때 처음부터 다시 받게 한다. **id까지 비운다** — 커서만 지우면 다음 로드가
         * "더 받기"로 들어가 옛 id 위에 붙고, 방금 보관을 해제한 포스트가 목록에 남는다. */
        mutating func invalidate() {
            ids = []
            nextCursor = nil
            hasLoaded = false
        }
    }

    private(set) var posts: [UUID: Post] = [:]
    private(set) var feed = List()
    private(set) var bookmarks = List()
    /* 사용자별 포스트 목록. 내 프로필과 타인 프로필이 같은 경로를 쓰므로(`/users/:id/posts`)
     * 하나로 둔다 — 나만 따로 두면 같은 페이징 코드가 둘이 된다. */
    private(set) var userLists: [UUID: List] = [:]

    @ObservationIgnored private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func post(id: UUID) -> Post? { posts[id] }

    // MARK: - 목록

    /* 목록들이 경로만 다르고 나머지가 같다. 한 번만 쓰고 **읽고 쓰는 법**을 받는다 —
     * 같은 코드를 늘리면 페이징 버그도 같이 늘어난다.
     *
     * 키 경로가 아니라 접근자인 이유: 사용자별 목록은 `[UUID: List]` 사전이라 쓰기 가능한 키
     * 경로를 만들 수 없다. 이전 판은 임시 프로퍼티(`scratch`)를 거쳤는데, 그 슬롯이 `await`를
     * 넘어가며 공유돼 **`guard !isLoading` 중복 방지가 사용자별 목록에서만 무력화**됐다
     * (초기 로드 중 pull-to-refresh면 두 요청이 같은 슬롯에 쓰고 나중 것이 이긴다).
     * 접근자는 매번 실제 자리를 읽고 쓰므로 그 창이 없다. */
    private func load(
        path: String,
        refresh: Bool,
        get: () -> List,
        set: (List) -> Void
    ) async {
        guard !get().isLoading else { return }
        if !refresh, !get().canLoadMore, get().hasLoaded { return }

        let cursor = refresh ? nil : get().nextCursor
        let generation = generation
        var starting = get()
        starting.isLoading = true
        starting.failure = nil
        set(starting)
        defer {
            if generation == self.generation {
                var done = get()
                done.isLoading = false
                set(done)
            }
        }

        do {
            let page = try await client.send(
                .get, path,
                query: cursor.map { ["cursor": $0] } ?? [:],
                as: PostPage.self
            )
            /* 기다리는 사이 계정이 바뀌었으면 이 응답은 **이전 계정의 것**이다. 쓰면 방금 비운
             * 자리에 옛 목록이 되살아난다 — `reset()`이 한 일을 정확히 되돌린다. 로그아웃 버튼이
             * 프로필 탭 툴바에 있고 그 화면이 열리며 목록을 받으므로, 실제로 겹치는 창이다. */
            guard generation == self.generation else { return }
            merge(page.items)
            let ids = page.items.map(\.id)
            /* 새로고침은 갈아끼우고, 더 받기는 뒤에 붙인다. 붙일 때 중복을 거르는 이유는
             * 커서 경계에서 같은 항목이 두 번 올 수 있기 때문이다 — `ForEach`가 같은 id를
             * 두 번 만나면 SwiftUI가 목록을 잘못 그린다. */
            var updated = get()
            if refresh {
                updated.ids = ids
            } else {
                let known = Set(updated.ids)
                updated.ids += ids.filter { !known.contains($0) }
            }
            updated.nextCursor = page.nextCursor
            updated.hasLoaded = true
            set(updated)
        } catch {
            guard generation == self.generation else { return }
            var failed = get()
            failed.failure = message(for: error)
            set(failed)
        }
    }

    func loadFeed(refresh: Bool = false) async {
        await load(path: "/feed", refresh: refresh,
                   get: { self.feed }, set: { self.feed = $0 })
    }

    func loadBookmarks(refresh: Bool = false) async {
        await load(path: "/users/me/bookmarks", refresh: refresh,
                   get: { self.bookmarks }, set: { self.bookmarks = $0 })
    }

    func userList(id: UUID) -> List { userLists[id] ?? List() }

    /// 사용자별 포스트 목록. 내 프로필과 타인 프로필이 같은 경로를 쓴다.
    func loadUser(id: UUID, refresh: Bool = false) async {
        await load(path: "/users/\(id.path)/posts", refresh: refresh,
                   get: { self.userList(id: id) }, set: { self.userLists[id] = $0 })
    }

    // MARK: - 한 건

    /* 상세로 들어갈 때 부른다. 목록에서 온 포스트가 이미 사전에 있어도 다시 받는다 —
     * 목록 항목은 받아 온 시점의 사본이고, 그 사이 댓글 수·반응이 바뀐다. */
    func refresh(id: UUID) async {
        do {
            merge([try await client.send(.get, "/posts/\(id.path)", as: Post.self)])
        } catch let error as APIError where error.isNotFound {
            // 남이 지웠거나 공개 범위에서 빠졌다. 화면이 "삭제됨"을 그리도록 사전에서 뺀다.
            forget(id)
        } catch {
            // 상세는 이미 목록에서 온 값을 그리고 있다. 갱신 실패로 화면을 비우지 않는다.
        }
    }

    // MARK: - 쓰기

    /* 보관 토글. 서버가 **결과 상태**를 돌려주므로(`{bookmarked}`) 앱이 뒤집어 짐작하지 않는다 —
     * 두 기기에서 같은 포스트를 눌렀을 때 짐작이 어긋난다.
     *
     * 보관 목록은 갱신하지 않고 **다음에 열 때 다시 받는다.** 커서 키가 "보관한 시각"이라
     * 중간에 끼워 넣으면 서버가 줄 순서와 달라진다.
     *
     * 실패를 목록의 `failure`에 담지 않고 **던진다.** 담아 봐야 `PostList`는 목록이 비었을 때만
     * 그 문구를 그리므로, 포스트가 있는 화면에서 보관을 눌러 실패하면 아무 일도 일어나지
     * 않는다 — 사용자에게는 버튼이 고장난 것으로 보인다. 부른 화면이 자기 자리에 쓴다. */
    func toggleBookmark(id: UUID) async throws {
        guard let post = posts[id] else { return }
        let wanted = !post.bookmarked
        let result = try await client.send(
            wanted ? .put : .delete, "/posts/\(id.path)/bookmark",
            as: BookmarkResult.self
        )
        posts[id] = post.replacing(bookmarked: result.bookmarked)
        bookmarks.invalidate()
    }

    /* 반응(§7.3). 서버가 **바뀐 요약 전체**를 돌려주므로 앱이 수치를 더하고 빼지 않는다 —
     * 같은 포스트에 여러 사람이 동시에 반응하면 손으로 센 값은 금세 어긋난다.
     *
     * 같은 반응을 다시 누르면 취소(`DELETE`), 다른 반응이면 교체(`PUT`)다. 교체를 위해 먼저
     * 지울 필요가 없다 — 서버가 `PUT` 하나로 토글과 교체를 함께 처리한다.
     *
     * 실패는 `toggleBookmark`와 같은 이유로 던진다. */
    func react(id: UUID, type: ReactionType) async throws {
        guard let post = posts[id] else { return }
        let isCancel = post.reactions.mine?.known == type
        let summary: ReactionSummary = try await client.send(
            isCancel ? .delete : .put, "/posts/\(id.path)/reaction",
            body: isCancel ? nil : PutReactionBody(type: ServerEnum(type)),
            as: ReactionSummary.self
        )
        posts[id] = post.replacing(reactions: summary)
    }

    /// 삭제. 서버가 soft delete라 목록에서도 빠진다.
    func delete(id: UUID) async throws {
        try await client.send(.delete, "/posts/\(id.path)")
        forget(id)
    }

    /// 공유 링크(§7.1). 비공개 포스트는 서버가 거절한다(`POST_NOT_SHAREABLE`).
    func shareLink(id: UUID) async throws -> URL {
        let response = try await client.send(
            .get, "/posts/\(id.path)/share", as: ShareLinkResponse.self
        )
        guard let url = URL(string: response.url) else {
            throw APIError.malformedResponse(status: 200, snippet: response.url)
        }
        return url
    }

    // MARK: - 내부

    private func merge(_ items: [Post]) {
        for item in items { posts[item.id] = item }
    }

    private func forget(_ id: UUID) {
        posts[id] = nil
        feed.ids.removeAll { $0 == id }
        bookmarks.ids.removeAll { $0 == id }
        for key in userLists.keys {
            userLists[key]?.ids.removeAll { $0 == id }
        }
    }

    /// 방금 발행한 포스트를 피드 맨 앞에 놓는다. 새로고침을 기다리게 하면 저장이 실패한 것처럼 보인다.
    func insertPublished(_ post: Post) {
        posts[post.id] = post
        feed.ids.removeAll { $0 == post.id }
        feed.ids.insert(post.id, at: 0)
        // 내 목록에도 얹는다 — 프로필 그리드가 새로고침을 기다리지 않게.
        if userLists[post.author.id] != nil {
            userLists[post.author.id]?.ids.removeAll { $0 == post.id }
            userLists[post.author.id]?.ids.insert(post.id, at: 0)
        }
    }

    /* 계정이 바뀌었다. 받아 둔 것은 전부 이전 계정의 것이므로 버린다 —
     * **커서와 `hasLoaded`까지** 비워야 다음 계정이 처음부터 받는다(`CutinApp` 주석 참고).
     *
     * 세대를 올리는 것이 비우는 것만큼 중요하다. 비우는 순간 날아가 있던 요청이 뒤늦게
     * 돌아와 옛 목록을 되살리면, 비운 의미가 없다(`load`의 `generation` 검사). */
    func reset() {
        generation += 1
        posts = [:]
        feed = List()
        bookmarks = List()
        userLists = [:]
    }

    /// 계정 세대. `reset()`이 올리고, 날아가 있던 요청이 자기 세대가 지났는지 본다.
    @ObservationIgnored private var generation = 0

    private func message(for error: any Error) -> String {
        switch error {
        case APIError.transport:
            return "서버에 연결할 수 없어요. 잠시 후 다시 시도해주세요"
        case APIError.server(_, _, let message, _):
            return message
        default:
            return "불러오지 못했어요. 잠시 후 다시 시도해주세요"
        }
    }
}

private extension Post {
    /// 서버가 돌려준 부분 상태를 얹은 사본. `Post`가 전부 `let`이라 이 자리에서 만든다 —
    /// 서버 응답 타입을 var로 열면 어디서든 값이 바뀔 수 있게 된다.
    func replacing(bookmarked: Bool? = nil, reactions: ReactionSummary? = nil) -> Post {
        Post(
            id: id, author: author, template: template, frame: frame,
            status: status, visibility: visibility, caption: caption,
            thumbnailCutIndex: thumbnailCutIndex, cuts: cuts, composed: composed,
            publishedAt: publishedAt, createdAt: createdAt,
            commentCount: commentCount,
            reactions: reactions ?? self.reactions,
            bookmarked: bookmarked ?? self.bookmarked
        )
    }
}
