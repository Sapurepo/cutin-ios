/* 피드 — 스파이크는 "합성 결과가 실제 파일로 남는가"를 눈으로 확인하는 용도라 한 화면으로 끝낸다.
 * 무한 스크롤·반응·댓글(명세 §4.1, §7)은 범위 밖. */

import SwiftUI

struct FeedView: View {
    @Environment(FeedStore.self) private var store
    @Environment(\.palette) private var palette

    @State private var selected: ComposedPost?

    var body: some View {
        Group {
            if store.posts.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .background(palette.bg)
        .navigationTitle("CUTIN")
        .sheet(item: $selected) { post in
            detail(post)
        }
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
                if let recovery = store.recovery {
                    recoveryNotice(recovery)
                }
                ForEach(store.posts) { post in
                    card(post)
                        .onTapGesture { selected = post }
                }
            }
            .padding(.horizontal, Spacing.x4)
            .padding(.vertical, Spacing.x4)
        }
    }

    /// 인덱스를 잃고 사진에서 목록을 되살린 경우 — 조용히 넘어가면 사용자는 캡션이 왜 사라졌는지 모른다.
    /// 격리 파일이 있으면 "손상", 없으면 목록 파일 자체가 사라진 것이다.
    private func recoveryNotice(_ recovery: IndexRecovery) -> some View {
        VStack(alignment: .leading, spacing: Spacing.x1) {
            Text(recovery.quarantine == nil
                 ? "목록 파일이 없어 사진 \(recovery.recovered)장에서 복구했어요"
                 : "목록이 손상돼 사진 \(recovery.recovered)장에서 복구했어요")
                .font(Typography.bodyText)
                .foregroundStyle(palette.textPrimary)
            Text("캡션과 보정 정보는 복구되지 않았어요")
                .font(Typography.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                        // 삭제 실패는 인덱스가 온전하다는 뜻이라 목록도 그대로 둔다.
                        // 사용자에게 알리는 배너는 하드닝 브랜치에서 붙인다.
                        try? store.delete(post)
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

    /// 합성 출력 폭과 같다 — 이보다 크게 요청해도 없는 픽셀이 생기지 않는다.
    private static let maxPixel: CGFloat = 1080

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
