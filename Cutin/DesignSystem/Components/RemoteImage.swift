/* 서버 이미지 — 카드·그리드 셀·아바타 세 곳이 쓴다(호출부 3곳).
 *
 * `AsyncImage`를 그대로 쓰되 두 가지를 더한다: **도착하면 페이드인**, 기다리는 동안 **숨 쉬는
 * 자리**(스켈레톤). 0.3.0은 회색 사각형에 사진이 툭 나타났다(감사 G4) — 첫 화면에서 사진이
 * 열 장 도착하면 열 번 튄다.
 *
 * 캐시를 따로 만들지 않는 이유는 `AvatarView`와 같다 — `/media/content/…`는 인증 없이
 * URLSession 공유 캐시가 듣는다. */

import SwiftUI

struct RemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    /// 자리를 채우는 색. 아바타처럼 뒤에 이미 그림(이니셜)이 있으면 `.clear`.
    var placeholder: Color? = nil
    /// 기다리는 동안 반짝일지. 이니셜 위에 겹치는 아바타는 끈다.
    var shimmers = true

    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            placeholder ?? palette.surfaceSunken
            if let url {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: Duration.medium))) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: contentMode)
                            .transition(.opacity)
                    case .empty:
                        if shimmers { Shimmer() }
                    case .failure:
                        // 깨진 아이콘을 그리지 않는다 — 자리 색이 곧 "없음"이다. 사용자가 할 일이 없다.
                        EmptyView()
                    @unknown default:
                        EmptyView()
                    }
                }
            }
        }
    }
}

/* 스켈레톤 반짝임. 자리 색 위로 옅은 띠가 한 방향으로 지나간다 — "받는 중"을 스피너 없이 말한다.
 * `accessibilityReduceMotion`이면 움직이지 않고 자리 색만 남는다. */
struct Shimmer: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            LinearGradient(
                colors: [.clear, palette.surface.opacity(0.55), .clear],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: width * 0.6)
            .offset(x: phase * width)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                    phase = 1.4
                }
            }
        }
        .clipped()
        .allowsHitTesting(false)
    }
}

#Preview("RemoteImage", traits: .sizeThatFitsLayout) {
    HStack(spacing: Spacing.x4) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            let palette = Palette.of(scheme)
            HStack(spacing: Spacing.x3) {
                RemoteImage(url: nil).frame(width: 96, height: 96).clipShape(.rect(cornerRadius: Radius.md))
                RemoteImage(url: URL(string: "https://example.invalid/never.jpg"))
                    .frame(width: 96, height: 128).clipShape(.rect(cornerRadius: Radius.md))
            }
            .padding(Spacing.x4)
            .background(palette.bg)
            .environment(\.palette, palette)
        }
    }
}
