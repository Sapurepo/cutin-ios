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
        VStack(spacing: Spacing.x3) {
            Text("아직 남긴 컷이 없어요")
                .font(Typography.headline)
                .foregroundStyle(palette.textPrimary)
            Text("촬영 탭에서 첫 컷을 찍어보세요")
                .font(Typography.bodyText)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private func card(_ post: ComposedPost) -> some View {
        VStack(alignment: .leading, spacing: Spacing.x2) {
            if let image = store.image(for: post) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(.rect(cornerRadius: Radius.md))
            }

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
                        .strokedBorder(Capsule(), color: palette.border)
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
                if let image = store.image(for: post) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(Spacing.x4)
                }
            }
            .background(palette.bg)
            .navigationTitle("포스트")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .destructiveAction) {
                    Button("삭제", role: .destructive) {
                        store.delete(post)
                        selected = nil
                    }
                }
            }
        }
    }
}
