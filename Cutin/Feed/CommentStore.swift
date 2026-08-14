/* 댓글 — 명세 §7.2.
 *
 * `PostStore`에 넣지 않고 따로 둔 이유: 댓글은 **포스트마다 목록이 하나**라 상태가
 * `[포스트 id: 목록]` 모양이고, 포스트 자체와는 수명이 다르다. 포스트는 피드를 스크롤하는
 * 동안 계속 쌓이지만 댓글은 연 포스트의 것만 필요하다.
 *
 * 그래도 앱이 소유한다(화면이 아니라). 상세 화면을 나갔다 다시 들어올 때 목록을 처음부터
 * 받으면, 방금 쓴 댓글이 사라졌다가 나타난다.
 *
 * 댓글 수는 `Post.commentCount`에 있고 여기서 고치지 않는다 — 상세를 다시 열 때
 * `PostStore.refresh(id:)`가 서버 값을 받아 온다. 두 곳에서 세면 갈라진다. */

import Foundation
import Observation

@MainActor
@Observable
final class CommentStore {
    struct List {
        var items: [Comment] = []
        var nextCursor: String?
        var isLoading = false
        var hasLoaded = false
        var failure: String?
    }

    private(set) var lists: [UUID: List] = [:]
    /// 지금 보내는 중인 댓글. 버튼을 잠그는 데 쓴다.
    private(set) var isPosting = false

    @ObservationIgnored private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func list(for postId: UUID) -> List { lists[postId] ?? List() }

    func load(postId: UUID, refresh: Bool = false) async {
        var list = list(for: postId)
        guard !list.isLoading else { return }
        if !refresh, list.hasLoaded, list.nextCursor == nil { return }

        let cursor = refresh ? nil : list.nextCursor
        list.isLoading = true
        list.failure = nil
        lists[postId] = list
        defer {
            var done = self.list(for: postId)
            done.isLoading = false
            lists[postId] = done
        }

        do {
            let page = try await client.send(
                .get, "/posts/\(postId.path)/comments",
                query: cursor.map { ["cursor": $0] } ?? [:],
                as: CommentPage.self
            )
            var updated = self.list(for: postId)
            if refresh {
                updated.items = page.items
            } else {
                let known = Set(updated.items.map(\.id))
                updated.items += page.items.filter { !known.contains($0.id) }
            }
            updated.nextCursor = page.nextCursor
            updated.hasLoaded = true
            lists[postId] = updated
        } catch {
            var failed = self.list(for: postId)
            failed.failure = message(for: error)
            lists[postId] = failed
        }
    }

    /* 쓴 댓글을 **맨 뒤에** 붙인다. 서버 목록이 오래된 순이므로(커서가 작성 시각) 방금 쓴 것이
     * 마지막이다. 목록을 다시 받지 않는 이유는 그러면 쓰는 순간 화면이 위로 튀기 때문이다. */
    func post(postId: UUID, body: String) async -> Bool {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isPosting else { return false }
        isPosting = true
        defer { isPosting = false }

        do {
            let comment = try await client.send(
                .post, "/posts/\(postId.path)/comments",
                body: CreateCommentBody(body: trimmed), as: Comment.self
            )
            var list = self.list(for: postId)
            list.items.append(comment)
            list.failure = nil
            lists[postId] = list
            return true
        } catch {
            var list = self.list(for: postId)
            list.failure = message(for: error)
            lists[postId] = list
            return false
        }
    }

    func delete(postId: UUID, commentId: UUID) async {
        do {
            try await client.send(.delete, "/posts/\(postId.path)/comments/\(commentId.path)")
            var list = self.list(for: postId)
            list.items.removeAll { $0.id == commentId }
            lists[postId] = list
        } catch {
            var list = self.list(for: postId)
            list.failure = message(for: error)
            lists[postId] = list
        }
    }

    /// 계정이 바뀌었다. 남의 계정으로 받아 둔 댓글을 그대로 두면 "삭제" 메뉴 판정
    /// (`comment.author.id == session.userId`)이 새 계정 기준으로 다시 그려진다.
    func reset() {
        lists = [:]
    }

    private func message(for error: any Error) -> String {
        switch error {
        case APIError.transport:
            return "서버에 연결할 수 없어요. 잠시 후 다시 시도해주세요"
        case APIError.server(_, _, let message, _):
            return message
        default:
            return "댓글을 불러오지 못했어요"
        }
    }
}
