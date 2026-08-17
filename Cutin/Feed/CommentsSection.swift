/* 댓글 — 명세 §7.2. 상세 화면 **안에** 바로 보인다.
 *
 * 0.3.0은 "댓글 N개 ›"를 눌러 별도 화면으로 갔다. 두 번 들어가야 대화가 보이는 SNS는 없고,
 * 반응 줄 바로 아래 댓글이 이어져야 카드가 대화처럼 읽힌다(레퍼런스 setlog). 입력칸은 상세
 * 화면 바닥에 붙는다(`CommentComposer`, `safeAreaInset`) — 키보드가 올라오면 화면이 그만큼
 * 줄고 목록은 그대로 스크롤된다.
 *
 * 목록이 **오래된 순**이다(커서가 작성 시각). 채팅과 같은 순서라 방금 쓴 것이 맨 아래에 붙고,
 * 그래서 새 댓글을 쓸 때 화면이 위로 튀지 않는다. 다음 페이지는 더 오래된 것이라 **위**에
 * "이전 댓글 더 보기"로 받는다 — 스크롤 위치에 기대 자동으로 받으면 상세를 열자마자 두 페이지가
 * 연달아 온다. */

import SwiftUI

struct CommentsSection: View {
    let post: Post

    @Environment(CommentStore.self) private var comments
    @Environment(AuthSession.self) private var session
    @Environment(\.palette) private var palette

    @State private var reportTarget: UUID?

    private var list: CommentStore.List { comments.list(for: post.id) }

    /// 다 받았으면 받은 수가 정확하고, 아니면 서버 요약이 정확하다.
    private var count: Int {
        list.hasLoaded && list.nextCursor == nil ? list.items.count : max(post.commentCount, list.items.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.x3) {
            Text(count == 0 ? "댓글" : "댓글 \(count)")
                .font(Typography.label)
                .foregroundStyle(palette.textSecondary)

            if list.items.isEmpty {
                if list.isLoading || !list.hasLoaded {
                    ProgressView().tint(palette.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.x3)
                } else {
                    Text("아직 아무도 말을 걸지 않았어요. 첫 마디를 남겨보세요")
                        .font(Typography.body)
                        .foregroundStyle(palette.textSecondary)
                        .padding(.vertical, Spacing.x2)
                }
            } else {
                if list.nextCursor != nil {
                    Button {
                        Task { await comments.load(postId: post.id) }
                    } label: {
                        Text(list.isLoading ? "받는 중…" : "이전 댓글 더 보기")
                            .font(Typography.label)
                    }
                    .buttonStyle(.glass)
                    .disabled(list.isLoading)
                    .frame(maxWidth: .infinity)
                }
                // 댓글 사이 4pt(+ 행 안 여백 8) — 한 덩어리로 읽히되 어디서 갈리는지는 보이게.
                LazyVStack(alignment: .leading, spacing: Spacing.x1) {
                    ForEach(list.items, id: \.id) { comment in
                        row(comment)
                    }
                }
            }

            if let failure = list.failure {
                Text(failure)
                    .font(Typography.caption)
                    .foregroundStyle(palette.danger)
            }
        }
        .sheet(item: $reportTarget) { id in
            ReportSheet(targetType: .comment, targetId: id)
        }
        .task(id: post.id) { await comments.load(postId: post.id) }
    }

    /* 한 줄: 아바타 · 이름 + 시각 · 본문. 세로 여백을 넉넉히 둔다 — 댓글은 훑는 게 아니라 읽는
     * 것이라 줄이 붙어 있으면 누가 어디까지 말했는지 흐려진다. 배경 면은 없다 — 카드 위에 카드를
     * 얹으면 대화가 상자 더미로 보인다. 행은 여백과 아바타로만 갈린다. */
    private func row(_ comment: Comment) -> some View {
        HStack(alignment: .top, spacing: Spacing.x3) {
            NavigationLink(value: Route.userProfile(comment.author.id)) {
                AvatarView(url: comment.author.avatarUrl,
                           nickname: comment.author.nickname, size: 32)
            }
            .buttonStyle(.plain)
            .disabled(comment.author.id == session.userId)

            VStack(alignment: .leading, spacing: Spacing.x1) {
                HStack(spacing: Spacing.x2) {
                    Text(comment.author.nickname ?? "이름 없음")
                        .font(Typography.subheadline)
                        .foregroundStyle(palette.textPrimary)
                    if let date = comment.createdAt.isoDate {
                        Text(date.casual())
                            .font(Typography.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                Text(comment.body)
                    .font(Typography.body)
                    .foregroundStyle(palette.textPrimary)
                    .lineSpacing(3)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.x2)
        .contentShape(.rect)
        /* 내 댓글은 지우고, 남의 댓글은 신고한다. 서버가 남의 댓글 삭제를 막으므로
         * 지우기 버튼을 두면 거짓 약속이다. */
        .contextMenu {
            if comment.author.id == session.userId {
                Button("삭제", role: .destructive) {
                    Task { await comments.delete(postId: post.id, commentId: comment.id) }
                }
            } else {
                Button("신고하기") { reportTarget = comment.id }
            }
        }
    }
}

/* 입력칸 — 상세 화면 바닥. 성공했을 때만 비운다: 먼저 비우면 실패한 순간 사용자가 쓴 글이
 * 사라지고, 길게 쓴 댓글일수록 그 손실이 크다. */
struct CommentComposer: View {
    let postId: UUID
    /// 나타나자마자 포커스(키보드) — "댓글 남기러 왔다"는 진입에서만. 푸시 전환이 끝난 뒤에 준다.
    var focusesOnAppear = false
    /// 성공한 뒤 — 상세가 포스트 요약(댓글 수)을 다시 받는 데 쓴다.
    var onPosted: () async -> Void = {}

    @Environment(CommentStore.self) private var comments
    @Environment(\.palette) private var palette

    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: Spacing.x2) {
            TextField("댓글 남기기", text: $draft, axis: .vertical)
                .font(Typography.body)
                .lineLimit(1...4)
                .focused($isFocused)
                .padding(.horizontal, Spacing.x4)
                .padding(.vertical, Spacing.x3)
                .background(palette.surface, in: .capsule)
                .tokenBorder(Capsule(), color: isFocused ? palette.brand : palette.border)
                .animation(Motion.quick, value: isFocused)

            Button {
                Task { await send() }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(canSend ? palette.accentOn : palette.textSecondary)
                    .frame(width: 40, height: 40)
                    .background(canSend ? palette.accent : palette.surfaceSunken, in: .circle)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .animation(Motion.quick, value: canSend)
        }
        .padding(.horizontal, Spacing.x4)
        .padding(.vertical, Spacing.x2)
        .background(palette.bg)
        .task {
            guard focusesOnAppear else { return }
            // 푸시 전환(약 0.35초)이 끝난 뒤 — 전환 중에 키보드가 올라오면 화면이 두 번 움직인다.
            try? await Task.sleep(for: .milliseconds(450))
            isFocused = true
        }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !comments.isPosting
    }

    private func send() async {
        if await comments.post(postId: postId, body: draft) {
            draft = ""
            isFocused = false
            await onPosted()
        }
    }
}

/// `sheet(item:)`이 `Identifiable`을 요구한다. 신고 대상 id를 그대로 신원으로 쓴다.
extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}
