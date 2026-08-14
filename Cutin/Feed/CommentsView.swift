/* 댓글 — 명세 §7.2.
 *
 * 시트가 아니라 **푸시**다. 시트로 띄우면 키보드가 올라올 때 목록이 반쪽이 되고, 답글을 쓰면서
 * 포스트를 다시 보려면 시트를 내려야 한다.
 *
 * 목록이 **오래된 순**이다(커서가 작성 시각). 채팅과 같은 순서라 방금 쓴 것이 맨 아래에 붙고,
 * 그래서 새 댓글을 쓸 때 화면이 위로 튀지 않는다. */

import SwiftUI

struct CommentsView: View {
    let postId: UUID

    @Environment(CommentStore.self) private var comments
    @Environment(AuthSession.self) private var session
    @Environment(\.palette) private var palette

    @State private var draft = ""
    @State private var reportTarget: UUID?
    @FocusState private var isFocused: Bool

    private var list: CommentStore.List { comments.list(for: postId) }

    var body: some View {
        VStack(spacing: 0) {
            content
            composer
        }
        .background(palette.bg)
        .navigationTitle("댓글")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $reportTarget) { id in
            ReportSheet(targetType: .comment, targetId: id)
        }
        .task { await comments.load(postId: postId) }
    }

    @ViewBuilder
    private var content: some View {
        if list.items.isEmpty {
            if list.isLoading || !list.hasLoaded {
                ProgressView().tint(palette.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyStateView(
                    title: "첫 댓글을 남겨보세요",
                    message: "아직 아무도 말을 걸지 않았어요",
                    systemImage: "bubble.left"
                )
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.x4) {
                    /* 더 받기가 **위쪽**에 있다. 오래된 순 목록이라 다음 페이지는 더 최신이 아니라
                     * 더 오래된 것이고, 그것이 위로 붙는다. */
                    if list.nextCursor != nil {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .task { await comments.load(postId: postId) }
                    }
                    ForEach(list.items, id: \.id) { comment in
                        row(comment)
                    }
                }
                .padding(Spacing.x4)
            }
        }
    }

    private func row(_ comment: Comment) -> some View {
        HStack(alignment: .top, spacing: Spacing.x3) {
            NavigationLink(value: Route.userProfile(comment.author.id)) {
                AvatarView(url: comment.author.avatarUrl,
                           nickname: comment.author.nickname, size: 32)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(comment.author.nickname ?? "이름 없음")
                    .font(Typography.chip)
                    .foregroundStyle(palette.textSecondary)
                Text(comment.body)
                    .font(Typography.bodyText)
                    .foregroundStyle(palette.textPrimary)
            }
            Spacer(minLength: 0)
        }
        /* 내 댓글은 지우고, 남의 댓글은 신고한다. 서버가 남의 댓글 삭제를 막으므로
         * 지우기 버튼을 두면 거짓 약속이다. */
        .contextMenu {
            if comment.author.id == session.userId {
                Button("삭제", role: .destructive) {
                    Task { await comments.delete(postId: postId, commentId: comment.id) }
                }
            } else {
                Button("신고하기") { reportTarget = comment.id }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: Spacing.x2) {
            if let failure = list.failure {
                Text(failure)
                    .font(Typography.caption)
                    .foregroundStyle(palette.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: Spacing.x2) {
                TextField("댓글 남기기", text: $draft, axis: .vertical)
                    .font(Typography.bodyText)
                    .lineLimit(1...4)
                    .focused($isFocused)
                    .padding(Spacing.x3)
                    .background(palette.surface, in: .rect(cornerRadius: Radius.sm))
                    .tokenBorder(RoundedRectangle(cornerRadius: Radius.sm), color: palette.border)

                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(canSend ? palette.accent : palette.border)
                }
                .disabled(!canSend)
            }
        }
        .padding(Spacing.x4)
        .background(palette.bg)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !comments.isPosting
    }

    private func send() async {
        /* 성공했을 때만 입력칸을 비운다. 먼저 비우면 실패한 순간 사용자가 쓴 글이 사라지고,
         * 길게 쓴 댓글일수록 그 손실이 크다. */
        if await comments.post(postId: postId, body: draft) {
            draft = ""
            isFocused = false
        }
    }
}

/// `sheet(item:)`이 `Identifiable`을 요구한다. 신고 대상 id를 그대로 신원으로 쓴다.
extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}
