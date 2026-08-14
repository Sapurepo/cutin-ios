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

    /* 세 목록이 경로만 다르고 나머지가 같다. 키 경로로 받아 한 번만 쓴다 —
     * 같은 코드를 셋으로 늘리면 페이징 버그도 셋이 된다. */
    private func load(
        _ list: ReferenceWritableKeyPath<PostStore, List>,
        path: String,
        refresh: Bool
    ) async {
        guard !self[keyPath: list].isLoading else { return }
        if !refresh, !self[keyPath: list].canLoadMore, self[keyPath: list].hasLoaded { return }

        let cursor = refresh ? nil : self[keyPath: list].nextCursor
        self[keyPath: list].isLoading = true
        self[keyPath: list].failure = nil
        defer { self[keyPath: list].isLoading = false }

        do {
            let page = try await client.send(
                .get, path,
                query: cursor.map { ["cursor": $0] } ?? [:],
                as: PostPage.self
            )
            merge(page.items)
            let ids = page.items.map(\.id)
            /* 새로고침은 갈아끼우고, 더 받기는 뒤에 붙인다. 붙일 때 중복을 거르는 이유는
             * 커서 경계에서 같은 항목이 두 번 올 수 있기 때문이다 — `ForEach`가 같은 id를
             * 두 번 만나면 SwiftUI가 목록을 잘못 그린다. */
            if refresh {
                self[keyPath: list].ids = ids
            } else {
                let known = Set(self[keyPath: list].ids)
                self[keyPath: list].ids += ids.filter { !known.contains($0) }
            }
            self[keyPath: list].nextCursor = page.nextCursor
            self[keyPath: list].hasLoaded = true
        } catch {
            self[keyPath: list].failure = message(for: error)
        }
    }

    func loadFeed(refresh: Bool = false) async {
        await load(\.feed, path: "/feed", refresh: refresh)
    }

    func loadBookmarks(refresh: Bool = false) async {
        await load(\.bookmarks, path: "/users/me/bookmarks", refresh: refresh)
    }

    func userList(id: UUID) -> List { userLists[id] ?? List() }

    /* 사용자별 목록은 사전이라 키 경로를 쓸 수 없다. 같은 페이징을 두 번 쓰지 않으려고
     * 임시 프로퍼티를 거쳐 `load`를 재사용한다 — 사전 항목에 직접 쓰는 키 경로를 만들 수 없어서다. */
    func loadUser(id: UUID, refresh: Bool = false) async {
        scratch = userList(id: id)
        await load(\.scratch, path: "/users/\(id.path)/posts", refresh: refresh)
        userLists[id] = scratch
    }

    /// `loadUser`가 잠깐 쓰는 자리. 목록 하나씩만 불러오므로 겹치지 않는다.
    @ObservationIgnored private var scratch = List()

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
     * 중간에 끼워 넣으면 서버가 줄 순서와 달라진다. */
    func toggleBookmark(id: UUID) async {
        guard let post = posts[id] else { return }
        let wanted = !post.bookmarked
        do {
            let result = try await client.send(
                wanted ? .put : .delete, "/posts/\(id.path)/bookmark",
                as: BookmarkResult.self
            )
            posts[id] = post.replacing(bookmarked: result.bookmarked)
            bookmarks.invalidate()
        } catch {
            feed.failure = message(for: error)
        }
    }

    /* 반응(§7.3). 서버가 **바뀐 요약 전체**를 돌려주므로 앱이 수치를 더하고 빼지 않는다 —
     * 같은 포스트에 여러 사람이 동시에 반응하면 손으로 센 값은 금세 어긋난다.
     *
     * 같은 반응을 다시 누르면 취소(`DELETE`), 다른 반응이면 교체(`PUT`)다. 교체를 위해 먼저
     * 지울 필요가 없다 — 서버가 `PUT` 하나로 토글과 교체를 함께 처리한다. */
    func react(id: UUID, type: ReactionType) async {
        guard let post = posts[id] else { return }
        let isCancel = post.reactions.mine?.known == type
        do {
            let summary: ReactionSummary = try await client.send(
                isCancel ? .delete : .put, "/posts/\(id.path)/reaction",
                body: isCancel ? nil : PutReactionBody(type: ServerEnum(type)),
                as: ReactionSummary.self
            )
            posts[id] = post.replacing(reactions: summary)
        } catch {
            feed.failure = message(for: error)
        }
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
