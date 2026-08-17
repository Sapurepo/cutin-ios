/* 포스트 미리보기 — 프로필 그리드에서 **길게 누르면** 뜨는 팝업.
 *
 * 그리드 셀은 대표 컷 한 장이라 어떤 포스트인지 다 보이지 않는다. 상세로 들어가지 않고 합성본과
 * 캡션을 크게 보고, 바로 아래 글래스 막대에서 자주 쓰는 동작(댓글 · 공유 · 보관 · 고정 해제)을
 * 끝낸다. 뒤는 스크림이고 스크림을 누르면 닫힌다 — 팝업의 "밖"이 곧 닫기다.
 *
 * 탭 트리 위에 그린다(`RootView` overlay) — 그래야 탭바·내비게이션 바까지 어두워진다.
 * 포스트는 id로 되찾는다(규칙 4) — 보관·고정 해제가 사전을 바꾸면 팝업도 그 값을 그린다. */

import SwiftUI

struct PostPeekView: View {
    let id: UUID
    let onClose: () -> Void

    @Environment(PostStore.self) private var store
    @Environment(AuthSession.self) private var session
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.palette) private var palette

    @State private var notice: String?
    @State private var shareURL: URL?
    @State private var isBusy = false

    var body: some View {
        ZStack {
            // 스크림 — 누르면 닫힌다. 카드 바깥 전부가 닫기 영역이다.
            palette.scrim
                .ignoresSafeArea()
                .contentShape(.rect)
                .onTapGesture { onClose() }

            if let post = store.post(id: id) {
                VStack(spacing: Spacing.x4) {
                    card(post)
                    bar(post)
                    if let notice {
                        Text(notice)
                            .font(Typography.caption)
                            .foregroundStyle(.white.opacity(0.85))
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, Spacing.x5)
                .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
        }
        .sheet(item: $shareURL) { url in
            ShareSheet(url: url)
        }
        .onAppear { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    }

    // MARK: - 카드

    private func card(_ post: Post) -> some View {
        VStack(alignment: .leading, spacing: Spacing.x3) {
            /* 합성본 높이는 화면의 절반까지 — 세로 스트립이 화면을 다 차지하면 아래 막대와 스크림이
             * 사라져 "팝업"이 아니라 상세가 된다. 비율은 `PostImage`가 지키므로 폭이 따라 줄고,
             * 카드 폭 안에서 가운데에 놓인다. */
            PostImage(post: post)
                .containerRelativeFrame(.vertical) { height, _ in height * 0.5 }
                .frame(maxWidth: .infinity)
            HStack(spacing: Spacing.x2) {
                AvatarView(url: post.author.avatarUrl, nickname: post.author.nickname, size: 26)
                Text(post.author.nickname ?? "이름 없음")
                    .font(Typography.subheadline)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: Spacing.x2)
                if let date = post.displayDate {
                    Text(date.casual())
                        .font(Typography.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            if let caption = post.caption, !caption.isEmpty {
                Text(caption)
                    .font(Typography.body)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
            }
            ReactionDigest(post: post)
        }
        .padding(Spacing.x3)
        .raised(cornerRadius: Radius.lg)
        // 카드를 누르면 상세로 — 미리보기는 "더 보고 싶다"의 앞 단계다.
        .contentShape(.rect)
        .onTapGesture { openDetail(post) }
    }

    // MARK: - 글래스 막대

    /* 동작은 넷까지 — 댓글 · 공유 · 보관 · (내 것이고 고정돼 있으면) 고정 해제. 삭제·신고는
     * 여기 두지 않는다: 미리보기는 "잠깐 보고 한 번 누르는" 자리이지 되돌리기 어려운 결정을
     * 내리는 자리가 아니다. */
    private func bar(_ post: Post) -> some View {
        let isMine = post.author.id == session.userId
        return GlassEffectContainer(spacing: Spacing.x2) {
            HStack(spacing: Spacing.x2) {
                action("댓글", systemImage: "bubble.left") { openComments(post) }
                action("공유", systemImage: "square.and.arrow.up") { Task { await share(post) } }
                action(post.bookmarked ? "보관 해제" : "보관",
                       systemImage: post.bookmarked ? "bookmark.fill" : "bookmark") {
                    Task { await toggleBookmark(post) }
                }
                if isMine, post.isPinned {
                    action("고정 해제", systemImage: "pin.slash") { Task { await unpin(post) } }
                }
            }
            .padding(Spacing.x2)
            .glassEffect(.regular, in: .capsule)
        }
        .disabled(isBusy)
    }

    private func action(_ title: String, systemImage: String, _ perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            VStack(spacing: Spacing.x1) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .medium))
                Text(title)
                    .font(Typography.caption)
            }
            .foregroundStyle(palette.textPrimary)
            .frame(minWidth: 56)
            .padding(.vertical, Spacing.x2)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 동작

    /// 카드 → 상세. 팝업은 닫는다.
    private func openDetail(_ post: Post) {
        onClose()
        coordinator.profilePath.append(.postDetail(post.id))
    }

    /// 댓글 → 상세를 **입력칸에 포커스한 채로**(`Route.postComments`). 댓글을 남기러 온 것이다.
    private func openComments(_ post: Post) {
        onClose()
        coordinator.profilePath.append(.postComments(post.id))
    }

    private func share(_ post: Post) async {
        notice = nil
        do {
            shareURL = try await store.shareLink(id: post.id)
        } catch let error as APIError {
            notice = error.serverMessage ?? "공유 링크를 만들지 못했어요"
        } catch {
            notice = "공유 링크를 만들지 못했어요"
        }
    }

    private func toggleBookmark(_ post: Post) async {
        notice = nil
        do {
            try await store.toggleBookmark(id: post.id)
        } catch {
            notice = error.displayMessage(fallback: "보관을 바꾸지 못했어요")
        }
    }

    private func unpin(_ post: Post) async {
        notice = nil
        isBusy = true
        defer { isBusy = false }
        do {
            try await store.unpin(id: post.id)
        } catch let error as APIError {
            // 발행 후 수정을 아직 안 받는 서버는 POST_NOT_DRAFT를 낸다 — 사실대로 말한다.
            notice = error.serverMessage ?? "고정을 풀지 못했어요"
        } catch {
            notice = "고정을 풀지 못했어요"
        }
    }
}
