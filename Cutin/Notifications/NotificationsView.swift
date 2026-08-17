/* 인앱 알림 목록 — 명세 §10.
 *
 * 탭을 만들지 않고 피드 툴바에서 푸시한다. 5탭이 이미 명세(§4.2)로 확정돼 있고, 알림은
 * 하루에 몇 개 오는 목록이라 탭 하나를 상시 차지할 만한 무게가 아니다.
 *
 * 안 읽은 항목은 **화면에 뜬 것만** 읽음으로 표시한다. 여는 순간 전부 읽음 처리하면 스크롤해서
 * 본 적 없는 알림이 사라진다. */

import SwiftUI

struct NotificationsView: View {
    @Environment(NotificationStore.self) private var store
    @Environment(\.palette) private var palette

    var body: some View {
        Group {
            if !store.items.isEmpty {
                list
            } else if store.isLoading {
                ProgressView().tint(palette.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let failure = store.failure {
                /* 실패와 빈 목록을 가른다(`PostList`와 같은 판단). 실패에서 `hasLoaded`가 false로
                 * 남는데, 이전 판은 그 상태를 "로딩 중"으로 그려서 **스피너가 영원히 돌았다** —
                 * 재시도할 길도 없었다. */
                EmptyStateView(title: "불러오지 못했어요", message: failure,
                               systemImage: "exclamationmark.triangle") {
                    Button("다시 시도") { Task { await store.load(refresh: true) } }
                        .primaryGlassButton(tint: palette.accent)
                }
            } else if !store.hasLoaded {
                ProgressView().tint(palette.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyStateView(
                    title: "새 소식이 없어요",
                    message: "친구가 반응하거나 댓글을 남기면 여기 모여요",
                    systemImage: "bell"
                )
            }
        }
        .background(palette.bg)
        .navigationTitle("알림")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await store.flushRead()
            await store.load(refresh: true)
            await store.loadUnreadCount()
        }
        .task {
            await store.load()
            await store.loadUnreadCount()
        }
        // 화면을 나갈 때 모인 읽음을 보낸다. 항목마다 보내면 스크롤 한 번에 왕복이 수십 번이다.
        .onDisappear { Task { await store.flushRead() } }
    }

    private var list: some View {
        List {
            ForEach(store.items, id: \.id) { item in
                NavigationLink(value: destination(for: item)) {
                    row(item)
                }
                // 화면에 나타난 것만 읽음 후보다.
                .onAppear { store.markVisible(item.id) }
            }
            if store.nextCursor != nil {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .task { await store.load() }
            }
        }
        .listStyle(.plain)
    }

    private func destination(for item: AppNotification) -> Route {
        switch item.targetType.known {
        case .post: return .postDetail(item.targetId)
        /* 모르는 대상은 사람으로 보낸다. 서버가 대상 종류를 늘려도 **누가 보냈는지는 늘 있으므로**
         * 빈 화면으로 떨어지지 않는다. */
        case .user, nil: return .userProfile(item.actor.id)
        }
    }

    private func row(_ item: AppNotification) -> some View {
        HStack(spacing: Spacing.x3) {
            AvatarView(url: item.actor.avatarUrl, nickname: item.actor.nickname, size: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(text(for: item))
                    .font(Typography.bodyText)
                    .foregroundStyle(palette.textPrimary)
                if let date = item.createdAt.isoDate {
                    Text(date, format: .relative(presentation: .named))
                        .font(Typography.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            }

            Spacer(minLength: 0)

            // 안 읽음 표시. 배지 대신 점 하나 — 개수가 아니라 여부만 말하면 되는 자리다.
            if item.readAt == nil {
                Circle().fill(palette.brand).frame(width: 8, height: 8)
            }
        }
    }

    /* 문구는 앱이 만든다. 서버가 알림에 문장을 싣지 않고 종류만 주기 때문이다
     * (`type`·`actor`·`targetType`). 모르는 종류는 일반 문구로 떨어진다 — 서버가 종류를
     * 늘려도 목록이 비지 않는다. */
    private func text(for item: AppNotification) -> String {
        let name = item.actor.nickname ?? "누군가"
        switch item.type.known {
        case .comment: return "\(name)님이 댓글을 남겼어요"
        case .reaction: return "\(name)님이 반응을 남겼어요"
        case .follow: return "\(name)님이 회원님을 팔로우해요"
        case nil: return "\(name)님의 새 소식이 있어요"
        }
    }
}

extension String {
    /* 서버가 주는 ISO 8601 문자열을 `Date`로. 계약 타입이 `Date`로 디코드하지 않는 이유는
     * `Contracts.swift` 머리말에 있다 — 형식이 하나만 어긋나도 페이지가 통째로 사라진다.
     * 여기서 실패하면 시각만 안 그린다. */
    var isoDate: Date? {
        String.isoParser.date(from: self) ?? String.isoParserNoFraction.date(from: self)
    }

    nonisolated(unsafe) private static let isoParser: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let isoParserNoFraction = ISO8601DateFormatter()
}
