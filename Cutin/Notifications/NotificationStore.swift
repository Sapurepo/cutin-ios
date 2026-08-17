/* 인앱 알림과 알림 설정 — 명세 §3.3 / §10.
 *
 * ## 미읽음 수를 목록에서 세지 않는다
 *
 * `GET /notifications/unread-count`가 따로 있다. 목록에서 `readAt == nil`을 세면 **받아 온
 * 페이지 안에서만** 참이라, 스크롤하지 않은 사용자에게는 항상 20 이하로 보인다.
 *
 * ## 읽음은 눈에 보인 것만
 *
 * 화면에 뜬 알림만 읽음으로 표시한다. 목록을 여는 순간 전부 읽음 처리하면, 스크롤해서 본 적도
 * 없는 알림이 사라진다. 서버가 한 번에 100개까지 받으므로(`maxItems`) 묶어 보낸다. */

import Foundation
import Observation

@MainActor
@Observable
final class NotificationStore {
    private(set) var items: [AppNotification] = []
    private(set) var nextCursor: String?
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var failure: String?

    /// 서버가 세어 준 미읽음 수. 배지가 이 값을 쓴다.
    private(set) var unread = 0

    private(set) var preferences: NotificationPreferences?
    private(set) var isSavingPreferences = false

    @ObservationIgnored private let client: APIClient
    /// 아직 읽음 처리를 보내지 않은 id. 화면에 뜬 것이 모인다.
    @ObservationIgnored private var pendingRead: Set<UUID> = []

    init(client: APIClient) {
        self.client = client
    }

    // MARK: - 목록

    func load(refresh: Bool = false) async {
        guard !isLoading else { return }
        if !refresh, hasLoaded, nextCursor == nil { return }

        let cursor = refresh ? nil : nextCursor
        let generation = generation
        isLoading = true
        failure = nil
        defer {
            if generation == self.generation { isLoading = false }
        }

        do {
            let page = try await client.send(
                .get, "/notifications",
                query: cursor.map { ["cursor": $0] } ?? [:],
                as: NotificationPage.self
            )
            // 기다리는 사이 계정이 바뀌었으면 이전 계정의 알림이다(`reset()` 참고).
            guard generation == self.generation else { return }
            if refresh {
                items = page.items
            } else {
                let known = Set(items.map(\.id))
                items += page.items.filter { !known.contains($0.id) }
            }
            nextCursor = page.nextCursor
            hasLoaded = true
        } catch {
            guard generation == self.generation else { return }
            failure = message(for: error)
        }
    }

    func loadUnreadCount() async {
        let generation = generation
        // 실패는 삼킨다 — 배지가 잠깐 옛 값이어도 화면이 망가지지 않는다.
        if let result = try? await client.send(
            .get, "/notifications/unread-count", as: UnreadCount.self
        ), generation == self.generation {
            unread = result.count
        }
    }

    /* 계정이 바뀌었다. 알림은 전부 받는 사람 기준이라 한 줄도 남길 수 없다 — 목록·배지가
     * 이전 계정 것으로 남고, `pendingRead`가 남으면 **다음 계정의 토큰으로 남의 알림을
     * 읽음 처리**하러 간다. 세대 검사는 `PostStore.reset()`과 같은 이유다. */
    func reset() {
        generation += 1
        items = []
        nextCursor = nil
        /* `isLoading`도 내린다. 날아가 있던 요청의 `defer`는 세대가 지나 건드리지 못하므로
         * 여기서 내리지 않으면 **다음 로드가 영영 `guard !isLoading`에 막힌다** —
         * 하니스 ⑥ "이후 요청은 정상으로 채워진다"가 처음에 이걸로 실패했다.
         * (`PostStore`는 `List()` 통째 교체라 이 문제가 없다.) */
        isLoading = false
        hasLoaded = false
        failure = nil
        unread = 0
        preferences = nil
        pendingRead = []
    }

    /// 계정 세대. 날아가 있던 요청이 비운 자리를 되살리지 않도록 한다.
    @ObservationIgnored private var generation = 0

    // MARK: - 읽음

    /// 알림이 화면에 나타났다. 바로 보내지 않고 모았다가 `flushRead()`에서 한 번에 보낸다.
    func markVisible(_ id: UUID) {
        guard items.first(where: { $0.id == id })?.readAt == nil else { return }
        pendingRead.insert(id)
    }

    /* 모인 것을 보낸다. 화면을 나갈 때와 목록을 새로 받을 때 부른다.
     *
     * 서버 상한이 100개라 나눠 보낸다. 성공한 묶음만 목록에 반영하는 이유는, 중간에 끊겼을 때
     * 보내지 못한 것까지 읽음으로 그리면 다음에 열었을 때 다시 안 읽음으로 돌아가기 때문이다. */
    func flushRead() async {
        guard !pendingRead.isEmpty else { return }
        let generation = generation
        let batches = Array(pendingRead).chunked(into: 100)
        pendingRead = []

        for batch in batches {
            do {
                try await client.send(.post, "/notifications/read",
                                      body: MarkReadBody(ids: batch))
                // 보내는 사이 계정이 바뀌었으면 남은 묶음도, 반영도 이전 계정의 것이다.
                guard generation == self.generation else { return }
                let stamp = ISO8601DateFormatter().string(from: Date())
                items = items.map { $0.readAt == nil && batch.contains($0.id)
                    ? $0.markingRead(at: stamp) : $0 }
                unread = max(0, unread - batch.count)
            } catch {
                guard generation == self.generation else { return }
                // 못 보낸 것은 다시 모아 둔다 — 다음 기회에 보낸다.
                pendingRead.formUnion(batch)
            }
        }
    }

    // MARK: - 설정 (§3.3)

    func loadPreferences() async {
        let generation = generation
        if let loaded = try? await client.send(
            .get, "/users/me/notification-preferences", as: NotificationPreferences.self
        ), generation == self.generation {
            preferences = loaded
        }
    }

    /* 슬롯은 **하나 이상**이어야 한다(서버 `minItems: 1`). 마지막 슬롯을 끄려는 시도는 보내지
     * 않고 막는다 — 400을 받아 문구를 띄우는 것보다, 알림을 끄려면 토글이 따로 있다고 말하는
     * 편이 낫다. */
    func updatePreferences(slots: [NotificationSlot], pushEnabled: Bool) async {
        guard !slots.isEmpty, !isSavingPreferences else { return }
        isSavingPreferences = true
        failure = nil
        defer { isSavingPreferences = false }

        do {
            preferences = try await client.send(
                .put, "/users/me/notification-preferences",
                body: NotificationPreferencesBody(
                    slots: slots.map(ServerEnum.init), pushEnabled: pushEnabled
                ),
                as: NotificationPreferences.self
            )
        } catch {
            failure = message(for: error)
        }
    }

    private func message(for error: any Error) -> String {
        switch error {
        case APIError.transport:
            return "서버에 연결할 수 없어요. 잠시 후 다시 시도해주세요"
        case APIError.server(_, _, let message, _):
            return message
        default:
            return "알림을 불러오지 못했어요"
        }
    }
}

private extension AppNotification {
    func markingRead(at stamp: String) -> AppNotification {
        AppNotification(id: id, type: type, actor: actor, targetType: targetType,
                        targetId: targetId, readAt: stamp, createdAt: createdAt)
    }
}

extension Array {
    /// 서버 상한(100개)에 맞춰 나눈다.
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
