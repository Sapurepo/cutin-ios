/* 포스트 카드 — 피드(§4.1)·보관(§7.4) 두 목록이 같은 모양을 쓴다.
 *
 * 0.1.0은 로컬 JPEG를 직접 디코드했다. 지금은 서버가 준 URL이라 `RemoteImage`가 받는다 —
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
        RemoteImage(url: post.composed.flatMap { URL(string: $0.url) }, contentMode: .fit)
            .aspectRatio(ratio, contentMode: .fit)
            .clipShape(.rect(cornerRadius: Radius.md))
            /* 합성본이 곧 카드다 — 배경에서 뜨게 한다. 흰 프레임(가장 흔하다)이 오프화이트 배경과
             * 붙어 어디까지가 사진인지 안 보이던 것(감사·피드)을 그림자/헤어라인이 가른다. */
            .raised(cornerRadius: Radius.md)
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
            // 배지는 웜 포인트 — "지금 켜져 있는 것"의 색이다(토큰 머리말).
            if post.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(palette.brand, in: .circle)
                    .padding(4)
            }
        }
    }
}

extension Post {
    /// 화면에 쓸 시각. 발행 시각이 있으면 그것, 없으면 만든 시각이다.
    /// 파싱은 `String.isoDate`가 한다 — 알림 목록도 같은 형식을 읽는다.
    var displayDate: Date? { (publishedAt ?? createdAt).isoDate }

    /* 대표 컷을 **직접 지정**했는지(§6.3) — 지정한 것만 프로필 그리드 맨 앞에 고정된다.
     *
     * nil 검사가 아니다. 서버가 발행 시 `thumbnailCutIndex`를 `?? 0`으로 채우므로 발행된
     * 포스트는 **항상 non-null**이고, nil로 가르면 전부 핀이 붙는다(2026-08-17 감사 B3 —
     * 0.3.0 하니스는 스텁이 null을 줘서 못 잡았다). 관찰 가능한 계약은 "0 = 기본(첫 컷)"뿐이라
     * 첫 컷을 직접 골라도 기본과 같은 것으로 본다 — 어차피 같은 그림이다. 서버가 미지정을
     * null로 남기게 되면(cutin-backend#13) 그때 nil 검사로 돌아간다. */
    var isPinned: Bool { (thumbnailCutIndex ?? 0) != 0 }

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

    /* 고정을 앞으로 — 프로필 그리드가 쓴다(내 프로필·타인 프로필 두 곳).
     *
     * `sorted`가 아니라 filter 둘을 잇는다. Swift의 `sorted`는 안정성을 보장하지 않아
     * 같은 그룹 안의 서버 순서(발행 시각)가 뒤섞일 수 있다.
     *
     * **받아 온 페이지 안에서만 참이다** — 아직 안 받은 옛 포스트의 고정은 스크롤해야
     * 나타난다. 서버 정렬 지원이 생기면 이 함수는 사라진다(0.3.0 범위 문서 참고). */
    static func pinnedFirst(_ posts: [Post]) -> [Post] {
        posts.filter(\.isPinned) + posts.filter { !$0.isPinned }
    }
}
