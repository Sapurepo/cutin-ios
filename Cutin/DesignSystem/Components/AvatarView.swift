/* 원형 아바타 — 온보딩(§3.4)과 프로필(§8.1) 두 곳이 쓴다.
 *
 * 사진이 없으면 닉네임 첫 글자를 그린다. 이니셜 서체가 본문 계열(Pretendard)인 이유:
 * 이니셜은 보통 한글인데 Geist는 라틴 전용이라 한글에 걸면 시스템 폰트로 조용히 폴백한다.
 *
 * `AsyncImage`를 쓴다. `/media/content/…`는 인증을 요구하지 않고(키에 소유자·미디어 id가 들어가
 * 추측할 수 없다 — 계약에 그렇게 적혀 있다) URLSession 공유 캐시가 그대로 듣는다.
 * 앱이 캐시를 따로 만들면 서버가 이미지를 바꿨을 때 옛 사진이 남는다. */

import SwiftUI

struct AvatarView: View {
    let url: String?
    /// 사진이 없을 때 그릴 이니셜의 출처. 닉네임이 없으면 "C"로 떨어진다.
    let nickname: String?
    var size: CGFloat = 84

    @Environment(\.palette) private var palette

    private var initial: String {
        nickname?.first.map(String.init) ?? "C"
    }

    var body: some View {
        ZStack {
            Circle().fill(palette.accent)

            Text(initial)
                .font(Typography.font(.body, .semibold, size: size * 0.4))
                .foregroundStyle(palette.accentOn)

            if let url, let parsed = URL(string: url) {
                /* 로딩 중에는 이니셜을 그대로 둔다 — 회색 원을 끼우면 사진이 있는 사용자에게
                 * 화면을 열 때마다 빈 원이 한 번 번쩍인다. */
                AsyncImage(url: parsed) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.clear
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
    }
}

#Preview("AvatarView", traits: .sizeThatFitsLayout) {
    HStack(spacing: Spacing.x4) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            HStack(spacing: Spacing.x3) {
                AvatarView(url: nil, nickname: "네컷러버")
                AvatarView(url: nil, nickname: nil, size: 44)
                AvatarView(url: nil, nickname: "Ada", size: 28)
            }
            .padding(Spacing.x4)
            .background(Palette.of(scheme).bg)
            .environment(\.palette, Palette.of(scheme))
        }
    }
}
