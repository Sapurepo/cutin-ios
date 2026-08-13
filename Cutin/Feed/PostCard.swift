/* 포스트 카드 — 피드(§4.1)와 기록 보관(§7.4) 두 목록이 같은 모양을 쓴다.
 *
 * 이미지 디코드는 메인 액터 밖에서 하고 자리를 먼저 잡는다. 카드와 상세가 같은 크기
 * (저장 해상도)를 요청하므로 캐시 항목도 하나를 공유한다. */

import SwiftUI

struct PostCard: View {
    let post: ComposedPost

    @Environment(\.palette) private var palette

    var body: some View {
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
}

/// 합성 결과 이미지. 저장 폭보다 크게 요청해도 없는 픽셀이 생기지 않으므로 그 값을 상한으로 쓴다.
struct PostImage: View {
    let post: ComposedPost

    @Environment(FeedStore.self) private var store
    @Environment(\.palette) private var palette

    @State private var image: UIImage?

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
            image = await store.image(for: post, maxPixel: CutCompositor.saveWidth)
        }
    }
}
