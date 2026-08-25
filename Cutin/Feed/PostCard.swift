/* 포스트 카드 — 피드(§4.1)·보관(§7.4) 두 목록이 같은 모양을 쓴다.
 *
 * 0.1.0은 로컬 JPEG를 직접 디코드했다. 지금은 서버가 준 URL이라 `RemoteImage`가 받는다 —
 * `/media/content/…`는 인증을 요구하지 않고 URLSession 공유 캐시가 그대로 듣는다. */

import SwiftUI

struct PostCard: View {
    let post: Post

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.x3) {
            PostImage(post: post)

            HStack(spacing: Spacing.x2) {
                AvatarView(url: post.author.avatarUrl, nickname: post.author.nickname, size: 26)
                Text(post.author.nickname ?? "이름 없음")
                    .font(Typography.subheadline)
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: Spacing.x2)
                if let date = post.displayDate {
                    Text(date.casual())
                        .font(Typography.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            }

            if let caption = post.caption, !caption.isEmpty {
                Text(caption)
                    .font(Typography.body)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(3)
            }

            ReactionDigest(post: post)
        }
    }
}

/* 카드가 받은 반응·댓글의 요약 — 카드 맨 아래 한 줄.
 *
 * 받은 이모지를 **겹쳐 쌓고**(많이 받은 순, 셋까지) 총 개수를 붙인다. 이모지 다섯 개를 전부
 * 늘어놓지 않는다 — 카드에서는 "무슨 반응이 몇 개"가 아니라 "반응이 있다, 대화가 있다"만
 * 보이면 된다. 세는 건 상세다. 댓글은 말풍선 + 수. 둘 다 없으면 줄 자체가 없다 — 빈 줄에
 * "아직 없음"을 적으면 조용한 카드가 쓸쓸한 카드가 된다. */
struct ReactionDigest: View {
    let post: Post

    @Environment(\.palette) private var palette

    private var topEmojis: [String] {
        post.reactions.counts
            .filter { $0.count > 0 }
            .sorted { $0.count > $1.count }
            .prefix(3)
            .compactMap { $0.type.known?.emoji }
    }

    var body: some View {
        if post.reactions.total > 0 || post.commentCount > 0 {
            HStack(spacing: Spacing.x3) {
                if post.reactions.total > 0 {
                    HStack(spacing: Spacing.x1) {
                        // 많이 받은 것이 맨 앞·맨 위에 — HStack은 뒤의 뷰가 위에 그려지므로 z를 뒤집는다.
                        HStack(spacing: -6) {
                            ForEach(Array(topEmojis.enumerated()), id: \.offset) { index, emoji in
                                Text(emoji)
                                    .font(.system(size: 13))
                                    .padding(2)
                                    .background(palette.surface, in: .circle)
                                    .zIndex(Double(topEmojis.count - index))
                            }
                        }
                        Text("\(post.reactions.total)")
                            .font(Typography.label)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                if post.commentCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 12, weight: .medium))
                        Text("\(post.commentCount)")
                            .font(Typography.label)
                    }
                    .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/* 합성 결과 이미지.
 *
 * `composed`는 **발행 전에는 null**이라(계약상 required + nullable) 옵셔널로 다룬다.
 * 피드에는 발행된 것만 오지만, 같은 카드를 draft에 쓰게 되는 날 조용히 깨지지 않도록.
 *
 * 자리는 **합성본의 실제 픽셀 비율**로 잡는다 — 서버가 `complete` 때 받은 width·height를
 * 돌려준다. 그래야 이미지가 도착할 때 목록이 튀지 않고, 자리와 그림이 어긋나 자리색 띠가
 * 남지 않는다. 0.3.0은 템플릿 그리드 비율을 썼는데, 합성본은 프레임 여백과 푸터를 포함해
 * 그리드보다 늘 조금 길다 — 그 차이만큼 회색 띠가 카드 아래에 붙었다(0.4.0 리뷰).
 * 크기가 없으면(옛 미디어) 그리드 비율로 떨어진다. */
struct PostImage: View {
    let post: Post

    @Environment(\.palette) private var palette

    private var ratio: CGFloat {
        if let composed = post.composed, let width = composed.width, let height = composed.height,
           width > 0, height > 0 {
            return CGFloat(width) / CGFloat(height)
        }
        return 1 / CutGeometry.heightPerWidth(post.template.aspectRatio)
    }

    var body: some View {
        RemoteImage(url: post.composed.flatMap { URL(string: $0.url) }, contentMode: .fit)
            .aspectRatio(ratio, contentMode: .fit)
            /* 합성본이 곧 카드다 — 배경에서 뜨게 한다. 흰 프레임(가장 흔하다)이 오프화이트 배경과
             * 붙어 어디까지가 사진인지 안 보이던 것(감사·피드)을 그림자/헤어라인이 가른다.
             *
             * **모서리는 각지다.** 합성본은 사각형 파일이고, 프레임 여백이 얇으면 둥근 모서리가
             * 코너에서 테두리를 먹는다(포토부스 스트립에서 특히 심했다). */
            .raised(cornerRadius: 0)
    }
}

/* 그리드 셀 — 내 프로필과 타인 프로필 두 그리드가 쓴다(호출부 2곳 규칙).
 *
 * 카드와 달리 **정사각으로 잘라 넣고**, 합성본이 아니라 **대표 컷**을 보여준다(§6.3 ·
 * 0.3.0 제품 결정). 합성본은 세로 스트립이면 정사각 크롭에서 가운데 조각만 남지만,
 * 컷 한 장은 사진이라 크롭이 자연스럽다. 미지정이면 서버 기본과 같은 첫 컷이다.
 *
 * 직접 지정한 포스트에는 핀 배지를 단다 — 그리드 맨 앞 고정과 함께 §6.3의 소비처다. */
struct PostThumbnail: View {
    let post: Post

    @Environment(\.palette) private var palette

    /* 정사각 **자리를 먼저 잡고** 이미지는 overlay로 얹는다. ZStack에 `scaledToFill` 이미지를
     * 넣으면 이미지가 자기 비율대로 자리를 넓혀 셀 밖으로 넘치고, 옆 셀과 겹치며 핀 배지를
     * 가린다(2026-08-17 감사 B2 — 세로 컷이 많은 프로필에서 셀 높이가 제각각이었다). */
    var body: some View {
        Rectangle()
            .fill(palette.surfaceSunken)
            .aspectRatio(1, contentMode: .fit)
            .overlay { RemoteImage(url: post.gridImageURL) }
            .clipped()
            .overlay(alignment: .topTrailing) {
            // 배지는 켜진 것의 색(잉크 원 + 반대색 핀) — 토큰 머리말.
            if post.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.accentOn)
                    .padding(4)
                    .background(palette.brand, in: .circle)
                    .padding(4)
            }
        }
    }
}

/* 그리드 셀 하나의 **누름** — 내 프로필과 타인 프로필이 쓴다(호출부 2곳).
 *
 * 짧게 누르면 상세, 길게 누르면 미리보기. NavigationLink 대신 제스처를 직접 거는 이유는 링크 위에
 * 길게 누르기를 얹으면 손을 뗄 때 링크까지 눌리기 때문이고, 그러면 버튼의 눌림 표시가 사라진다 —
 * 그래서 눌림을 직접 그린다: 손가락이 닿아 있는 동안 흐려진다(피드 카드의 링크 눌림과 같은 감각).
 * 흐려지는 것은 닿고 잠깐(80ms) 뒤부터 — 스크롤을 시작하는 손가락도 처음엔 셀 위에 닿으므로,
 * 즉시 흐리면 스크롤할 때마다 깜빡인다(UIKit의 delaysContentTouches와 같은 이유).
 * VoiceOver에는 버튼 트레이트와 "미리보기" 액션을 준다(길게 누르기는 대응 제스처가 없다). */
struct PostGridCell: View {
    let post: Post
    let onTap: () -> Void
    let onLongPress: () -> Void

    @State private var isPressed = false
    @State private var pressTask: Task<Void, Never>?

    var body: some View {
        PostThumbnail(post: post)
            .contentShape(.rect)
            .opacity(isPressed ? 0.55 : 1)
            .animation(Motion.quick, value: isPressed)
            .onTapGesture(perform: onTap)
            .onLongPressGesture(minimumDuration: 0.35, maximumDistance: 12) {
                onLongPress()
            } onPressingChanged: { pressing in
                pressTask?.cancel()
                if pressing {
                    pressTask = Task {
                        try? await Task.sleep(for: .milliseconds(80))
                        if !Task.isCancelled { isPressed = true }
                    }
                } else {
                    isPressed = false
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(post.caption ?? "컷")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onTap() }
            .accessibilityAction(named: "미리보기") { onLongPress() }
    }
}

extension Post {
    /// 화면에 쓸 시각. 발행 시각이 있으면 그것, 없으면 만든 시각이다.
    /// 파싱은 `String.isoDate`가 한다 — 알림 목록도 같은 형식을 읽는다.
    var displayDate: Date? { (publishedAt ?? createdAt).isoDate }

    /* 프로필 그리드 맨 앞에 고정됐는지(§6.3).
     *
     * 서버가 `pinned`를 주면 그것이 답이다(cutin-backend#14 — 대표 컷과 별개의 값). 그 전 서버에는
     * 이 필드가 없어 대표 컷 인덱스로 가른다: 발행 시 미지정을 0으로 채우므로 0은 기본, 0이 아니면
     * 직접 고른 것 = 고정(2026-08-17 감사 B3의 임시 규칙). 새 서버가 배포되면 이 폴백은 사라진다. */
    var isPinned: Bool { pinned ?? ((thumbnailCutIndex ?? 0) != 0) }

    /* 그리드 셀에 그릴 이미지 — 대표 컷(미지정이면 첫 컷, 서버 기본과 같다).
     *
     * `cutIndex`로 찾고 배열 위치를 믿지 않는다 — 계약이 순서를 약속하지 않는다.
     * 지정 인덱스에 컷이 없으면(계약 위반) 첫 컷으로, 컷이 하나도 없으면 합성본으로
     * 내려간다 — 셀 하나가 빈 것보다 낫다. */
    var gridImageURL: URL? {
        let wanted = thumbnailCutIndex ?? 0
        let cut = cuts.first { $0.cutIndex == wanted }
            ?? cuts.min { $0.cutIndex < $1.cutIndex }
        guard let raw = cut?.media.url ?? composed?.url else { return nil }
        return URL(string: raw)
    }
}
