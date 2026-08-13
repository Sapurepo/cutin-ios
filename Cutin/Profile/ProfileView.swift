/* 프로필 탭 — 명세 §8.1: 닉네임·아바타 + 내 포스트 그리드.
 *
 * 닉네임·아바타는 **서버 프로필이 진실**이다(0.1.0의 UserDefaults `ProfileStore`는 지웠다 —
 * 그 값은 서버에 간 적이 없어 화면과 서버가 다른 이름을 말했다).
 *
 * ## 통계를 지웠다
 *
 * 0.1.0은 포스트 수·총 컷 수·보관 수를 셌다. 로컬 인덱스가 통째로 메모리에 있어 **셀 수
 * 있었기 때문**이다. 지금은 목록이 커서 페이지라 화면에 있는 것은 받아 온 몇 페이지뿐이고,
 * 그것을 세면 스크롤할수록 "포스트 수"가 늘어난다. 서버에 합계 API가 없으므로 세지 않는다 —
 * RN판의 하드코딩 통계를 이식하지 않은 것과 같은 이유다(거짓 수치는 없느니만 못하다).
 *
 * 설정 진입(§8.3)은 두지 않는다 — 알림·약관은 아직 열 화면이 없다. 로그아웃만 둔다. */

import SwiftUI

struct ProfileView: View {
    @Environment(PostStore.self) private var store
    @Environment(AuthSession.self) private var session
    @Environment(\.palette) private var palette

    @State private var isEditingNickname = false
    @State private var nicknameDraft = ""

    /// 3열 정사각 그리드 — 원본 RN판 프로필과 같은 밀도.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    private var profile: UserProfile? {
        if case .signedIn(let profile) = session.phase { return profile }
        return nil
    }

    private var posts: [Post] { store.mine.ids.compactMap(store.post(id:)) }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.x6) {
                header
                grid
            }
            .padding(.top, Spacing.x4)
        }
        .refreshable { await reload(refresh: true) }
        .background(palette.bg)
        .navigationTitle(AppTab.profile.title)
        .navigationDestination(for: Route.self) { route in
            switch route {
            case .postDetail(let id):
                PostDetailView(id: id)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("로그아웃") { Task { await session.signOut() } }
                    .font(Typography.chip)
            }
        }
        .alert("닉네임", isPresented: $isEditingNickname) {
            TextField("닉네임", text: $nicknameDraft)
            Button("저장") {
                let wanted = nicknameDraft.trimmingCharacters(in: .whitespaces)
                Task { await session.updateNickname(wanted) }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("프로필에 보여줄 이름을 정해주세요")
        }
        .task { await reload(refresh: false) }
    }

    private func reload(refresh: Bool) async {
        guard let id = session.userId else { return }
        await store.loadMine(authorId: id, refresh: refresh)
    }

    // MARK: - 상단

    private var header: some View {
        VStack(spacing: Spacing.x3) {
            AvatarPicker(url: profile?.avatarUrl, nickname: profile?.nickname,
                         allowsRemoval: true)

            Button {
                nicknameDraft = profile?.nickname ?? ""
                isEditingNickname = true
            } label: {
                HStack(spacing: Spacing.x1) {
                    Text(profile?.nickname ?? "닉네임 정하기")
                        .font(Typography.headline)
                        .foregroundStyle(profile?.nickname == nil
                                         ? palette.textSecondary : palette.textPrimary)
                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .buttonStyle(.plain)

            if let failure = session.failure {
                Text(failure)
                    .font(Typography.caption)
                    .foregroundStyle(palette.danger)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - 그리드

    @ViewBuilder
    private var grid: some View {
        if posts.isEmpty {
            if store.mine.isLoading || !store.mine.hasLoaded {
                ProgressView().tint(palette.textSecondary).padding(.top, Spacing.x8)
            } else {
                EmptyStateView(
                    title: "아직 남긴 컷이 없어요",
                    message: "가운데 촬영 버튼으로 첫 컷을 찍어보세요",
                    systemImage: AppTab.profile.systemImage
                )
                .padding(.top, Spacing.x8)
            }
        } else {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(posts, id: \.id) { post in
                    NavigationLink(value: Route.postDetail(post.id)) {
                        GridCell(post: post)
                    }
                    .buttonStyle(.plain)
                }

                if store.mine.nextCursor != nil {
                    ProgressView()
                        .tint(palette.textSecondary)
                        .task { await reload(refresh: false) }
                }
            }
        }
    }
}

/// 그리드 셀. 합성본을 정사각으로 잘라 넣는다 — 템플릿 비율이 제각각이라 셀 높이가 튀면
/// 그리드가 격자로 보이지 않는다.
private struct GridCell: View {
    let post: Post

    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            Rectangle().fill(palette.surfaceSunken)
            if let composed = post.composed, let url = URL(string: composed.url) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.clear
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipped()
    }
}
