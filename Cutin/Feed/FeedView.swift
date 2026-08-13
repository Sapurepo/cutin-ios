/* 피드 — 명세 §4.1.
 *
 * 상세는 시트가 아니라 **푸시**다. 시트는 "여기서 잠깐 보고 돌아온다"는 뜻인데, 상세에는
 * 삭제·보관처럼 목록을 바꾸는 동작이 있어 되돌아온 목록이 달라져 있다. 푸시는 그 관계를
 * 그대로 표현하고, 뒤로 가기가 시스템 제스처로 통일된다.
 *
 * 무한 스크롤(커서 페이징)은 넣지 않았다 — 이유는 PR 본문에 적었다. 로컬 인덱스는 이미
 * 메모리에 다 있고, 실제 비용은 이미지 디코드이며 그건 LazyVStack이 이미 미룬다. */

import SwiftUI

struct FeedView: View {
    @Environment(FeedStore.self) private var store
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            /* 안내는 목록 바깥에 둔다 — 인덱스를 읽지 못하면 목록이 비어서, 안내를 목록 안에
             * 넣으면 "설명이 필요한 바로 그 상황"에서만 안내가 사라진다. */
            indexNotice
                .padding(.horizontal, Spacing.x4)
                .padding(.top, Spacing.x4)

            if !store.posts.isEmpty {
                list
            } else if isWriteBlocked {
                // 촬영을 권하지 않는다 — 지금은 저장이 막혀 있어서 찍으면 잃는다.
                Spacer()
            } else {
                emptyState
            }
        }
        .background(palette.bg)
        .navigationTitle("CUTIN")
        .navigationDestination(for: Route.self) { route in
            switch route {
            case .postDetail(let id):
                PostDetailView(id: id)
            }
        }
    }

    private var isWriteBlocked: Bool {
        if case .unwritable = store.indexStatus { return true }
        return false
    }

    private var emptyState: some View {
        EmptyStateView(
            title: "아직 남긴 컷이 없어요",
            message: "가운데 촬영 버튼으로 첫 컷을 찍어보세요",
            systemImage: AppTab.home.systemImage
        )
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.x6) {
                ForEach(store.posts) { post in
                    NavigationLink(value: Route.postDetail(post.id)) {
                        PostCard(post: post)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.x4)
            .padding(.vertical, Spacing.x4)
        }
    }

    /* 인덱스를 정상적으로 읽지 못한 경우를 설명한다. 조용히 넘어가면 사용자는 캡션이 왜
     * 사라졌는지, 왜 저장이 안 되는지 알 방법이 없다. */
    @ViewBuilder
    private var indexNotice: some View {
        switch store.indexStatus {
        case .ok:
            EmptyView()

        case .recovered(let count, let quarantine):
            notice(
                title: quarantine == nil
                    ? "목록 파일이 없어 사진 \(count)장에서 복구했어요"
                    : "목록이 손상돼 사진 \(count)장에서 복구했어요",
                detail: "캡션과 보정 정보는 복구되지 않았어요"
            ) {
                Button("확인") { store.acknowledgeRecovery() }
                    .font(Typography.chip)
            }

        case .unwritable:
            // 원본을 덮어쓰지 않으려고 쓰기를 막은 상태라 사용자가 닫을 수 있는 안내가 아니다.
            notice(
                title: "목록을 읽을 수 없어요",
                detail: "저장된 목록을 잃지 않도록 새 저장과 삭제를 잠시 막았어요. 앱을 다시 켜보세요"
            ) { EmptyView() }
        }
    }

    private func notice<Action: View>(
        title: String,
        detail: String,
        @ViewBuilder action: () -> Action
    ) -> some View {
        HStack(alignment: .top, spacing: Spacing.x3) {
            VStack(alignment: .leading, spacing: Spacing.x1) {
                Text(title)
                    .font(Typography.bodyText)
                    .foregroundStyle(palette.textPrimary)
                Text(detail)
                    .font(Typography.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
            action()
        }
        .padding(Spacing.x3)
        .background(palette.surface, in: .rect(cornerRadius: Radius.sm))
        .tokenBorder(RoundedRectangle(cornerRadius: Radius.sm), color: palette.border)
    }
}
