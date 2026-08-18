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
 * 설정(§8.3)은 메뉴 하나로 둔다 — 알림 설정·효과음·로그아웃뿐이라 화면을 따로 만들 만큼이 아니다.
 * 약관·탈퇴는 아직 열 화면이 없다. */

import SwiftUI

struct ProfileView: View {
    @Environment(PostStore.self) private var store
    @Environment(AuthSession.self) private var session
    @Environment(PushRegistrar.self) private var push
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.palette) private var palette

    @State private var isEditingNickname = false
    @State private var nicknameDraft = ""
    @AppStorage(SoundEffects.enabledKey) private var soundEnabled = true

    /// 3열 정사각 그리드 — 원본 RN판 프로필과 같은 밀도.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    private var profile: UserProfile? {
        if case .signedIn(let profile) = session.phase { return profile }
        return nil
    }

    private var list: PostStore.List {
        session.userId.map(store.userList(id:)) ?? PostStore.List()
    }

    /// 직접 지정한 대표 컷이 있는 포스트를 맨 앞에 고정한다(§6.3 · 0.3.0 제품 결정).
    private var posts: [Post] { Post.pinnedFirst(list.ids.compactMap(store.post(id:))) }

    /* 큰 제목이 아니라 **인라인 제목**이다. 큰 제목 + `refreshable` + 화면보다 짧은 내용의 조합에서
     * 위로 밀면 제목이 반쯤 접힌 채 되돌아오지 않고, 실기기에서는 접힘/펼침이 반복되며 상단이
     * 떨렸다(사용자 신고). 이름과 아바타가 이미 머리이므로 큰 제목 "프로필"은 잃을 것이 없다. */
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
        .navigationBarTitleDisplayMode(.inline)
        .routeDestinations()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    NavigationLink("알림 설정", value: Route.notificationSettings)
                    // 효과음(`SoundEffects`)은 무음 스위치를 이미 따르므로 화면 하나를 만들 만큼이 아니다.
                    Toggle("효과음", isOn: $soundEnabled)
                    // §3.5 "도움말에서 재열람" — 온보딩 직후 한 번 본 팁을 다시 여는 자리다.
                    NavigationLink("도움말", value: Route.tips)
                    #if DEBUG
                    NavigationLink("디자인 카탈로그", value: Route.designCatalog)
                    #endif
                    Button("로그아웃") { Task { await signOut() } }
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("설정")
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

    /* 로그아웃 전에 푸시 토큰을 지운다. 한 기기를 두 사람이 쓰면 앞사람의 알림이 뒷사람에게
     * 가고, 서버는 토큰으로 지우므로 세션이 끝나기 전에 불러야 한다. */
    private func signOut() async {
        await push.revoke()
        await session.signOut()
    }

    private func reload(refresh: Bool) async {
        guard let id = session.userId else { return }
        await store.loadUser(id: id, refresh: refresh)
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
                        .font(Typography.title)
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
            if list.isLoading || !list.hasLoaded {
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
                    PostGridCell(post: post,
                                 onTap: { coordinator.push(.postDetail(post.id)) },
                                 onLongPress: { coordinator.peekPostId = post.id })
                }

                if list.nextCursor != nil {
                    ProgressView()
                        .tint(palette.textSecondary)
                        .task { await reload(refresh: false) }
                }
            }
        }
    }
}
