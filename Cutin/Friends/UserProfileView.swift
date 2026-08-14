/* 타인 프로필 — 명세 §9.
 *
 * 관계를 앱이 조합하지 않는다. 서버가 `following`·`followedBy`·`friend`·`blocking` 넷을
 * 그대로 주므로 버튼 문구도 그 값에서 나온다.
 *
 * ## 차단은 파괴적이라 확인을 받는다
 *
 * 서버가 차단 즉시 **양방향 팔로우와 친구 관계를 끊고**, 해제해도 복구하지 않는다
 * (컨트롤러 설명). 되돌릴 수 없는 동작이라 한 번 더 묻는다.
 *
 * 차단한 사람의 포스트는 목록을 만들지 않는다 — 서버가 어차피 안 보여주고, 화면에 빈 그리드를
 * 남기면 "차단했는데 왜 자리가 있지"가 된다. */

import SwiftUI

struct UserProfileView: View {
    let id: UUID

    @Environment(SocialStore.self) private var social
    @Environment(PostStore.self) private var posts
    @Environment(\.palette) private var palette

    @State private var isConfirmingBlock = false
    @State private var isReporting = false
    /// 팔로우·차단 실패. 관계는 눌러도 화면이 잠깐 그대로라, 문구가 없으면 버튼이 죽은 줄 안다.
    @State private var notice: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        ScrollView {
            if let profile = social.profile(id: id) {
                VStack(spacing: Spacing.x6) {
                    header(profile)
                    if profile.blocking {
                        blockedNotice
                    } else {
                        grid
                    }
                }
                .padding(.top, Spacing.x4)
            } else {
                ProgressView().tint(palette.textSecondary).padding(.top, Spacing.x8)
            }
        }
        .background(palette.bg)
        .navigationTitle(social.profile(id: id)?.nickname ?? "프로필")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("신고하기") { isReporting = true }
                    Button(social.profile(id: id)?.blocking == true ? "차단 해제" : "차단하기",
                           role: .destructive) {
                        if social.profile(id: id)?.blocking == true {
                            Task { await toggleBlock() }
                        } else {
                            isConfirmingBlock = true
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .confirmationDialog("이 사람을 차단할까요?", isPresented: $isConfirmingBlock,
                            titleVisibility: .visible) {
            Button("차단하기", role: .destructive) { Task { await toggleBlock() } }
            Button("취소", role: .cancel) {}
        } message: {
            Text("서로의 팔로우가 끊기고, 차단을 풀어도 되돌아오지 않아요")
        }
        .sheet(isPresented: $isReporting) {
            ReportSheet(targetType: .user, targetId: id)
        }
        .task {
            await social.loadProfile(id: id)
            await posts.loadUser(id: id)
        }
    }

    // MARK: - 상단

    private func header(_ profile: PublicProfile) -> some View {
        VStack(spacing: Spacing.x3) {
            AvatarView(url: profile.avatarUrl, nickname: profile.nickname)

            Text(profile.nickname ?? "이름 없음")
                .font(Typography.headline)
                .foregroundStyle(palette.textPrimary)

            Text("친구 \(profile.friendCount)명")
                .font(Typography.caption)
                .foregroundStyle(palette.textSecondary)

            if !profile.blocking { followButton(profile) }

            if let notice {
                Text(notice)
                    .font(Typography.caption)
                    .foregroundStyle(palette.danger)
                    .multilineTextAlignment(.center)
            }
        }
    }

    /* 버튼 문구가 관계를 말한다. **"팔로우"와 "맞팔로우"를 가르는 이유**: 상대가 이미 나를
     * 팔로우 중이면 누르는 순간 친구가 된다 — 그 결과를 미리 알려주는 편이 정직하다. */
    private func followButton(_ profile: PublicProfile) -> some View {
        Button {
            Task { await toggleFollow() }
        } label: {
            Text(label(for: profile)).primaryGlassLabel()
        }
        .primaryGlassButton(tint: profile.following ? palette.surface : palette.accent)
        .padding(.horizontal, Spacing.x8)
    }

    private func label(for profile: PublicProfile) -> String {
        if profile.friend { return "친구" }
        if profile.following { return "팔로잉" }
        return profile.followedBy ? "맞팔로우" : "팔로우"
    }

    // MARK: - 관계 바꾸기

    private func toggleFollow() async {
        notice = nil
        do {
            try await social.toggleFollow(id: id)
        } catch {
            notice = error.displayMessage(fallback: "관계를 바꾸지 못했어요")
        }
    }

    private func toggleBlock() async {
        notice = nil
        do {
            try await social.toggleBlock(id: id)
        } catch {
            notice = error.displayMessage(fallback: "차단을 바꾸지 못했어요")
        }
    }

    private var blockedNotice: some View {
        Text("차단한 사람이에요. 서로의 컷이 보이지 않아요")
            .font(Typography.caption)
            .foregroundStyle(palette.textSecondary)
            .padding(.top, Spacing.x8)
    }

    // MARK: - 그리드

    @ViewBuilder
    private var grid: some View {
        let list = posts.userList(id: id)
        let items = list.ids.compactMap(posts.post(id:))

        if items.isEmpty {
            if list.isLoading || !list.hasLoaded {
                ProgressView().tint(palette.textSecondary).padding(.top, Spacing.x8)
            } else {
                /* 볼 수 없는 것과 없는 것을 가르지 않는다 — 서버가 공개 범위로 걸러 주므로
                 * 앱은 어느 쪽인지 모르고, 알려 주면 그 자체가 정보 노출이다. */
                Text("보여줄 컷이 없어요")
                    .font(Typography.caption)
                    .foregroundStyle(palette.textSecondary)
                    .padding(.top, Spacing.x8)
            }
        } else {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(items, id: \.id) { post in
                    NavigationLink(value: Route.postDetail(post.id)) {
                        PostThumbnail(post: post)
                    }
                    .buttonStyle(.plain)
                }
                if list.nextCursor != nil {
                    ProgressView().task { await posts.loadUser(id: id) }
                }
            }
        }
    }
}
