/* 프레임 견본 — 칩 앞에 붙는 작은 그림. 배치 칩의 `TemplateGlyph`와 같은 자리, 같은 이유다.
 *
 * 이름만 있는 칩으로는 "하트"와 "곰돌이"가 그냥 두 글자다. 프레임이 여덟에서 열넷으로 늘면서
 * 장식 있는 것들이 전부 목록 끝에 붙었는데, 가로 스크롤 끝까지 밀어 본 사람만 만나게 된다.
 *
 * 장식 스트립 그림을 그대로 축소해 얹는다 — 서버가 이미 그 그림을 갖고 있으므로 별도의
 * 썸네일을 만들 이유가 없고, 무엇보다 **실제로 나올 그림**이다. */

import SwiftUI

struct FrameSwatch: View {
    let frame: Frame
    var height: CGFloat = 22
    var selected = false

    @Environment(\.palette) private var palette

    /// 합성본이 세로로 길다 — 견본도 같은 방향이어야 프레임으로 읽힌다.
    private var width: CGFloat { height * 0.82 }

    var body: some View {
        ZStack(alignment: .top) {
            Color(uiColor: UIColor(hexString: frame.background))

            if let url = frame.decorTopUrl.flatMap({ URL(string: $0, relativeTo: APIConfig.baseURL) }) {
                /* 자리색을 깔지 않는다(`.clear`). 스트립은 알파가 대부분이라 자리색을 두면
                 * 그림이 오기 전까지 프레임 배경 위에 회색 띠가 얹힌다. */
                RemoteImage(url: url, contentMode: .fit, placeholder: .clear, shimmers: false)
                    .frame(width: width)
            }
        }
        .frame(width: width, height: height)
        .clipShape(.rect(cornerRadius: 4))
        .tokenBorder(
            RoundedRectangle(cornerRadius: 4),
            color: selected ? palette.brand : palette.border
        )
        .accessibilityHidden(true)
    }
}
