/* 포스트 카드 — 피드(§4.1)·보관(§7.4) 두 목록이 같은 모양을 쓴다.
 *
 * 0.1.0은 로컬 JPEG를 직접 디코드했다. 지금은 서버가 준 URL이라 `AsyncImage`가 받는다 —
 * `/media/content/…`는 인증을 요구하지 않고 URLSession 공유 캐시가 그대로 듣는다. */

import SwiftUI

struct PostCard: View {
    let post: Post

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.x2) {
            PostImage(post: post)

            HStack(spacing: Spacing.x2) {
                AvatarView(url: post.author.avatarUrl, nickname: post.author.nickname, size: 22)
                Text(post.author.nickname ?? "이름 없음")
                    .font(Typography.chip)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
                if let date = post.displayDate {
                    Text(date, format: .dateTime.year().month().day())
                        .font(Typography.numeric)
                        .foregroundStyle(palette.textSecondary)
                }
            }

            if let caption = post.caption, !caption.isEmpty {
                Text(caption)
                    .font(Typography.bodyText)
                    .foregroundStyle(palette.textPrimary)
            }
        }
    }
}

/* 합성 결과 이미지.
 *
 * `composed`는 **발행 전에는 null**이라(계약상 required + nullable) 옵셔널로 다룬다.
 * 피드에는 발행된 것만 오지만, 같은 카드를 draft에 쓰게 되는 날 조용히 깨지지 않도록.
 *
 * 자리를 정사각으로 잡는 대신 **템플릿 비율**을 쓴다. 서버가 배치를 주므로 그릴 수 있고,
 * 그래야 이미지가 도착할 때 목록이 튀지 않는다(`strip4`는 세로로 길다). */
struct PostImage: View {
    let post: Post

    @Environment(\.palette) private var palette

    private var ratio: CGFloat {
        1 / CutGeometry.heightPerWidth(post.template.aspectRatio)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(palette.surfaceSunken)

            if let composed = post.composed, let url = URL(string: composed.url) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    ProgressView().tint(palette.textSecondary)
                }
            }
        }
        .aspectRatio(ratio, contentMode: .fit)
        .clipShape(.rect(cornerRadius: Radius.md))
    }
}

/* 그리드 셀 — 내 프로필과 타인 프로필 두 그리드가 쓴다(호출부 2곳 규칙).
 *
 * 카드와 달리 **정사각으로 잘라 넣는다.** 템플릿 비율이 제각각이라 셀 높이가 따라가면
 * 3열 격자가 격자로 보이지 않는다. */
struct PostThumbnail: View {
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

extension Post {
    /// 화면에 쓸 시각. 발행 시각이 있으면 그것, 없으면 만든 시각이다.
    /// 파싱은 `String.isoDate`가 한다 — 알림 목록도 같은 형식을 읽는다.
    var displayDate: Date? { (publishedAt ?? createdAt).isoDate }
}
