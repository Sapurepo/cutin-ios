/* 포스트 상세 — 명세 §7.
 *
 * 담은 것: §7.1 공유, §7.4 보관, §7.5 삭제, 그리고 사진 앱 저장
 * (`Info.plist`의 `NSPhotoLibraryAddUsageDescription`이 이미 약속한 기능이다).
 *
 * §7.2 댓글은 목록 화면으로 푸시하고, §7.3 반응은 여기에 줄로 둔다 — 반응은 누르고 끝이지만
 * 댓글은 쓰는 동안 키보드가 화면을 반으로 나눈다.
 *
 * 포스트를 값으로 받지 않고 id로 되찾는다(규칙 4) — 보관·삭제가 목록도 함께 바꾼다.
 *
 * ## 공유와 사진 저장이 서로 다른 것을 넘긴다
 *
 * §7.1 공유는 **서버 링크**다(`GET /posts/{id}/share`). 0.1.0은 서버가 없어 이미지 파일을
 * 넘겼는데, 링크가 있으면 받는 사람이 앱에서 열 수 있다. 사진 앱 저장은 여전히 이미지라
 * 합성본 바이트를 내려받아 넘긴다. */

import Photos
import SwiftUI

struct PostDetailView: View {
    let id: UUID

    @Environment(PostStore.self) private var store
    @Environment(AuthSession.self) private var session
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var notice: String?
    @State private var isSavingToPhotos = false
    @State private var shareURL: URL?
    @State private var isReporting = false

    var body: some View {
        Group {
            if let post = store.post(id: id) {
                content(post)
            } else {
                // 지워졌거나 볼 수 없게 됐다. 서버가 둘을 구별해 주지 않고, 할 일도 같다.
                EmptyStateView(
                    title: "볼 수 없는 포스트예요",
                    message: "지워졌거나 공개 범위에서 빠졌어요",
                    systemImage: "eye.slash"
                )
            }
        }
        .background(palette.bg)
        .navigationTitle("포스트")
        .navigationBarTitleDisplayMode(.inline)
        // 목록에서 온 값은 받아 온 시점의 사본이다. 열 때 한 번 갱신한다.
        .task { await store.refresh(id: id) }
    }

    private func content(_ post: Post) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.x4) {
                PostImage(post: post)
                author(post)
                if let caption = post.caption, !caption.isEmpty {
                    Text(caption)
                        .font(Typography.bodyText)
                        .foregroundStyle(palette.textPrimary)
                }
                if let notice { noticeLabel(notice) }
                reactions(post)
                commentsLink(post)
                actions(post)
            }
            .padding(Spacing.x4)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    // 남의 포스트는 지울 수 없다 — 서버가 404를 내므로 버튼을 두면 거짓 약속이다.
                    if post.author.id == session.userId {
                        Button("삭제", role: .destructive) { delete(post) }
                    } else {
                        Button("신고하기") { isReporting = true }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .sheet(isPresented: $isReporting) {
            ReportSheet(targetType: .post, targetId: post.id)
        }
    }

    // MARK: - 본문

    private func author(_ post: Post) -> some View {
        HStack(spacing: Spacing.x2) {
            // 내 포스트에서 내 프로필로 가지 않는다 — 탭이 이미 그 화면이다.
            NavigationLink(value: Route.userProfile(post.author.id)) {
                HStack(spacing: Spacing.x2) {
                    AvatarView(url: post.author.avatarUrl,
                               nickname: post.author.nickname, size: 28)
                    Text(post.author.nickname ?? "이름 없음")
                        .font(Typography.bodyText)
                        .foregroundStyle(palette.textPrimary)
                }
            }
            .buttonStyle(.plain)
            .disabled(post.author.id == session.userId)
            Spacer(minLength: 0)
            if let date = post.displayDate {
                Text(date, format: .dateTime.year().month().day().hour().minute())
                    .font(Typography.numeric)
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }

    private func noticeLabel(_ message: String) -> some View {
        Text(message)
            .font(Typography.caption)
            .foregroundStyle(palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /* 반응 줄(§7.3). 다섯 종류를 다 펼쳐 둔다 — 길게 눌러 고르는 방식은 처음 쓰는 사람이
     * 발견하지 못하고, 종류가 다섯뿐이라 한 줄에 들어간다.
     *
     * 수치는 서버 요약을 그대로 읽는다. 누른 순간 앱이 +1 하면 여러 사람이 동시에 반응할 때
     * 금세 어긋나고, 서버가 응답으로 바뀐 요약 전체를 주므로 그럴 이유도 없다. */
    private func reactions(_ post: Post) -> some View {
        HStack(spacing: Spacing.x2) {
            ForEach(ReactionType.allCases, id: \.self) { type in
                let count = post.reactions.counts.first { $0.type.known == type }?.count ?? 0
                let mine = post.reactions.mine?.known == type
                Button {
                    Task { await store.react(id: post.id, type: type) }
                } label: {
                    HStack(spacing: 2) {
                        Text(type.emoji)
                        if count > 0 {
                            Text("\(count)")
                                .font(Typography.chip)
                                .foregroundStyle(mine ? palette.accentOn : palette.textSecondary)
                        }
                    }
                    .padding(.horizontal, Spacing.x2)
                    .padding(.vertical, Spacing.x1)
                    .background(mine ? palette.accent : palette.surface, in: .capsule)
                    .tokenBorder(Capsule(), color: mine ? .clear : palette.border)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private func commentsLink(_ post: Post) -> some View {
        NavigationLink(value: Route.comments(post.id)) {
            HStack(spacing: Spacing.x2) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 15, weight: .medium))
                Text(post.commentCount == 0 ? "댓글 남기기" : "댓글 \(post.commentCount)개")
                    .font(Typography.bodyText)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
            }
            .foregroundStyle(palette.textPrimary)
            .padding(Spacing.x3)
            .background(palette.surface, in: .rect(cornerRadius: Radius.sm))
            .tokenBorder(RoundedRectangle(cornerRadius: Radius.sm), color: palette.border)
        }
        .buttonStyle(.plain)
    }

    private func actions(_ post: Post) -> some View {
        HStack(spacing: Spacing.x2) {
            /* 공유 링크는 **누른 뒤에** 받는다. 화면을 열 때마다 미리 받으면 비공개 포스트에서
             * 매번 403이 나고, 정작 쓰지도 않을 왕복을 목록 스크롤마다 만든다. */
            Button {
                Task { await prepareShare(post) }
            } label: {
                actionLabel("공유", systemImage: "square.and.arrow.up")
            }

            Button {
                Task { await saveToPhotos(post) }
            } label: {
                actionLabel(isSavingToPhotos ? "저장 중…" : "사진 앱에 저장",
                            systemImage: "arrow.down.to.line")
            }
            .disabled(isSavingToPhotos || post.composed == nil)

            Button {
                Task { await store.toggleBookmark(id: post.id) }
            } label: {
                actionLabel(post.bookmarked ? "보관 해제" : "보관",
                            systemImage: post.bookmarked ? "bookmark.fill" : "bookmark")
            }
        }
        .buttonStyle(.glass)
        .frame(maxWidth: .infinity)
        /* 링크가 준비되면 시스템 공유 시트를 띄운다. `ShareLink`는 값이 미리 있어야 해서
         * 왕복이 필요한 지금 구조에는 맞지 않는다. */
        .sheet(item: $shareURL) { url in
            ShareSheet(url: url)
        }
    }

    private func actionLabel(_ title: String, systemImage: String) -> some View {
        VStack(spacing: Spacing.x1) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
            Text(title)
                .font(Typography.chip)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.x2)
    }

    // MARK: - 동작

    private func delete(_ post: Post) {
        Task {
            do {
                try await store.delete(id: post.id)
                dismiss()
            } catch {
                notice = "삭제하지 못했어요. 잠시 후 다시 시도해주세요"
            }
        }
    }

    private func prepareShare(_ post: Post) async {
        notice = nil
        do {
            shareURL = try await store.shareLink(id: post.id)
        } catch let error as APIError {
            // 비공개 포스트는 서버가 막는다(`POST_NOT_SHAREABLE`). 서버 문구를 그대로 쓴다.
            notice = error.serverMessage ?? "공유 링크를 만들지 못했어요"
        } catch {
            notice = "공유 링크를 만들지 못했어요"
        }
    }

    /* 사진 앱 저장. 서버에서 합성본 바이트를 받아 임시 파일로 쓴 뒤 넘긴다 —
     * `PHAssetCreationRequest`는 URL이나 Data를 받는데, 원본 JPEG를 그대로 넘겨야
     * 다시 인코딩되며 화질이 깎이지 않는다.
     *
     * `.addOnly` 권한만 요청한다 — 읽기 권한은 필요하지도 않고 사용자에게 더 큰 요구다. */
    private func saveToPhotos(_ post: Post) async {
        guard let composed = post.composed, let url = URL(string: composed.url) else { return }
        isSavingToPhotos = true
        defer { isSavingToPhotos = false }
        notice = nil

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            notice = "사진 앱 접근이 허용되지 않았어요. 설정에서 허용할 수 있어요"
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }
            notice = "사진 앱에 저장했어요"
        } catch {
            notice = "사진 앱에 저장하지 못했어요"
        }
    }
}

extension ReactionType {
    /* 이모지는 **콘텐츠**다 — 디자인 토큰에 넣지 않는다. 서버가 종류를 늘리면 여기 한 줄이
     * 늘고, 모르는 값은 `ServerEnum`이 원시 문자열로 보존해 화면에서만 빠진다. */
    var emoji: String {
        switch self {
        case .like: return "👍"
        case .love: return "❤️"
        case .haha: return "😂"
        case .wow: return "😮"
        case .sad: return "😢"
        }
    }
}

/// `sheet(item:)`은 `Identifiable`을 요구한다. URL 자체를 신원으로 쓴다.
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

/// 시스템 공유 시트. `ShareLink`와 달리 값이 나중에 생겨도 띄울 수 있다.
private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
