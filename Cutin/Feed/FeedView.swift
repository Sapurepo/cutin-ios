/* 피드 — 스파이크는 "합성 결과가 실제 파일로 남는가"를 눈으로 확인하는 용도라 한 화면으로 끝낸다.
 * 무한 스크롤·반응·댓글(명세 §4.1, §7)은 범위 밖. */

import SwiftUI

struct FeedView: View {
    @Environment(FeedStore.self) private var store
    @Environment(\.palette) private var palette

    @State private var selected: ComposedPost?

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
        .sheet(item: $selected) { post in
            detail(post)
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
                    card(post)
                        .onTapGesture { selected = post }
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

    private func card(_ post: ComposedPost) -> some View {
        VStack(alignment: .leading, spacing: Spacing.x2) {
            PostImage(post: post)

            HStack(spacing: Spacing.x2) {
                Text(post.createdAt, format: .dateTime.year().month().day())
                    .font(Typography.numeric)
                    .foregroundStyle(palette.textSecondary)
                if post.filterID != .original {
                    Text(post.filterID.displayName)
                        .font(Typography.chip)
                        .foregroundStyle(palette.textSecondary)
                        .padding(.horizontal, Spacing.x2)
                        .padding(.vertical, 2)
                        .tokenBorder(Capsule(), color: palette.border)
                }
            }

            if !post.caption.isEmpty {
                Text(post.caption)
                    .font(Typography.bodyText)
                    .foregroundStyle(palette.textPrimary)
            }
        }
    }

    private func detail(_ post: ComposedPost) -> some View {
        NavigationStack {
            ScrollView {
                PostImage(post: post)
                    .padding(Spacing.x4)
            }
            .background(palette.bg)
            .navigationTitle("포스트")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .destructiveAction) {
                    Button("삭제", role: .destructive) {
                        // 실패했는데 시트를 닫으면 포스트는 남아 있고 삭제는 아무 일도 안 한 것처럼
                        // 보인다. 실패하면 화면에 머무른다 — 배너는 하드닝 브랜치에서 붙인다.
                        guard (try? store.delete(post)) != nil else { return }
                        selected = nil
                    }
                }
            }
        }
    }
}

/* 포스트 이미지 — 디코드를 메인 액터 밖으로 보내고 자리를 먼저 잡는다.
 * 카드와 상세가 같은 크기(저장 해상도)를 쓰므로 캐시 항목도 하나로 공유된다. */
private struct PostImage: View {
    let post: ComposedPost

    @Environment(FeedStore.self) private var store
    @Environment(\.palette) private var palette

    @State private var image: UIImage?

    /// 합성 출력 폭 — 이보다 크게 요청해도 없는 픽셀이 생기지 않는다.
    /// 상수를 여기 또 적으면 합성 폭을 바꿀 때 디코드 상한만 옛 값에 남는다.
    private static let maxPixel = CutCompositor.saveWidth

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                // 로드 전 레이아웃이 튀지 않게 정사각으로 자리를 잡는다 (템플릿 대부분이 1:1).
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(palette.surfaceSunken)
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .clipShape(.rect(cornerRadius: Radius.md))
        .task(id: post.id) {
            image = await store.image(for: post, maxPixel: Self.maxPixel)
        }
    }
}
