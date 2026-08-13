/* 프로필 탭 — 명세 §8.1의 로컬 범위: 닉네임 + 내 포스트 그리드 + 통계.
 *
 * 통계는 **로컬에서 참인 것만** 센다: 포스트 수·총 컷 수·보관 수.
 * RN판의 하드코딩 통계(`{posts:"24", friends:"132"}`)는 이식하지 않는다 — 거짓 수치를
 * 화면에 올리는 순간 릴리즈 스크린샷이 증거로서 무의미해진다. 친구·반응 수는 렌더하지 않는다.
 *
 * 총 컷 수는 인덱스의 `count`를 합산한다. 인덱스를 잃고 복구된 레코드(`recoveredFromFile`)는
 * 컷 수가 자리값이라 합산에서 뺀다 — 모르는 값을 아는 척 더하면 통계가 거짓이 된다.
 *
 * 설정 진입(§8.3)은 두지 않는다 — 로그아웃·알림·약관 전부 서버가 생겨야 의미가 있는
 * 항목이라 0.1.0에는 열 화면이 없다. */

import SwiftUI

struct ProfileView: View {
    @Environment(FeedStore.self) private var store
    @Environment(ArchiveStore.self) private var archive
    @Environment(ProfileStore.self) private var profile
    @Environment(\.palette) private var palette

    @State private var isEditingNickname = false
    @State private var nicknameDraft = ""

    /// 3열 정사각 그리드 — 원본 RN판 프로필과 같은 밀도.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.x6) {
                header
                stats
                grid
            }
            .padding(.top, Spacing.x4)
        }
        .background(palette.bg)
        .navigationTitle(AppTab.profile.title)
        .navigationDestination(for: Route.self) { route in
            switch route {
            case .postDetail(let id):
                PostDetailView(id: id)
            }
        }
        .alert("닉네임", isPresented: $isEditingNickname) {
            TextField("닉네임", text: $nicknameDraft)
            Button("저장") {
                profile.nickname = nicknameDraft.trimmingCharacters(in: .whitespaces)
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("프로필에 보여줄 이름을 정해주세요")
        }
    }

    // MARK: - 상단

    private var header: some View {
        VStack(spacing: Spacing.x3) {
            // 이니셜 원형 아바타. PhotosPicker는 읽기 권한 키가 추가로 필요해 0.2.0.
            Text(profile.initial)
                .font(Typography.font(.latin, .semibold, size: 34))
                .foregroundStyle(palette.accentOn)
                .frame(width: 84, height: 84)
                .background(palette.accent, in: .circle)

            Button {
                nicknameDraft = profile.nickname
                isEditingNickname = true
            } label: {
                HStack(spacing: Spacing.x1) {
                    Text(profile.nickname.isEmpty ? "닉네임 정하기" : profile.nickname)
                        .font(Typography.headline)
                        .foregroundStyle(profile.nickname.isEmpty
                                         ? palette.textSecondary : palette.textPrimary)
                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 통계

    private var stats: some View {
        HStack(spacing: 0) {
            stat(value: store.posts.count, label: "포스트")
            stat(value: totalCuts, label: "컷")
            stat(value: archivedCount, label: "보관")
        }
        .padding(.vertical, Spacing.x3)
        .background(palette.surface, in: .rect(cornerRadius: Radius.md))
        .tokenBorder(RoundedRectangle(cornerRadius: Radius.md), color: palette.border)
        .padding(.horizontal, Spacing.x4)
    }

    private var totalCuts: Int {
        store.posts
            .filter { $0.recoveredFromFile != true }
            .reduce(0) { $0 + $1.count.rawValue }
    }

    /// 보관 수는 id 집합 크기가 아니라 **실재하는 포스트와의 교집합**을 센다 —
    /// 집합에 남은 유령 id가 있어도 화면 수치는 참이어야 한다.
    private var archivedCount: Int {
        store.posts.count { archive.contains($0.id) }
    }

    private func stat(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(Typography.font(.latin, .semibold, size: 20))
                .foregroundStyle(palette.textPrimary)
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 그리드

    @ViewBuilder
    private var grid: some View {
        if store.posts.isEmpty {
            EmptyStateView(
                title: "아직 남긴 컷이 없어요",
                message: "가운데 촬영 버튼으로 첫 컷을 찍어보세요",
                systemImage: AppTab.profile.systemImage
            )
            .padding(.top, Spacing.x8)
        } else {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(store.posts) { post in
                    NavigationLink(value: Route.postDetail(post.id)) {
                        GridCell(post: post)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/* 그리드 셀 — 카드(`PostImage`)와 달리 셀 크기로만 디코드한다.
 * 1080px 디코드를 3열 그리드에 그대로 쓰면 화면당 화소가 9배로 든다. */
private struct GridCell: View {
    let post: ComposedPost

    @Environment(FeedStore.self) private var store
    @Environment(\.palette) private var palette

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(palette.surfaceSunken)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipped()
        .task(id: post.id) {
            // 3열 셀의 실제 픽셀 폭(@3x 기준 약 400px)에 여유를 둔 값.
            image = await store.image(for: post, maxPixel: 480)
        }
    }
}
