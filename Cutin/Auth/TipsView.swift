/* 서비스 팁 — 명세 §3.5. 캐러셀 안내, 마지막에 "시작하기" → 메인 진입.
 *
 * 온보딩(닉네임)을 마친 직후 한 번 보여주고, 그 뒤로는 프로필 설정 메뉴의 "도움말"로만
 * 열린다 — 명세의 "다시 보지 않기 + 도움말에서 재열람 가능"이다. 본 적 여부는 기기에
 * 남는다(`UserDefaults`) — 계정 상태가 아니라 이 기기에서의 안내 여부이고, 서버에 대응
 * 필드도 없다. 재설치하면 다시 한 번 보게 되는데, 도움말이 한 번 더 뜨는 것은 사고가 아니다.
 *
 * ## 팁 세 장이 이제야 생긴 이유
 *
 * 0.1.0·0.2.0에서 이 화면을 미룬 근거는 "보여줄 팁이 정해지지 않았다 — 지어내면 그게 곧
 * 거짓말이다"였다. 지금은 다르다: 세 장 모두 **실제로 있는 기능만** 말한다. 촬영 방식 둘과
 * 컷 수는 서버 템플릿의 사실이고, 24시간 이어쓰기는 §5.3의 확정 정책이고, 공개 범위·반응·
 * 댓글은 0.2.0에 들어갔다. 약속이 아니라 설명이 됐으므로 화면을 만든다. */

import SwiftUI

struct TipsView: View {
    /// nil이면 재열람(도움말에서 푸시) — 마지막 버튼이 화면을 닫는 것으로 끝난다.
    /// 값이 있으면 온보딩 직후의 게이트 — "시작하기"가 이 클로저로 메인 진입을 연다.
    let onStart: (() -> Void)?

    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var page = 0

    private enum Tip: Int, CaseIterable {
        case shoot, compose, share

        var title: String {
            switch self {
            case .shoot: return "오늘을 컷으로 남겨요"
            case .compose: return "찍고 나서 천천히 꾸며요"
            case .share: return "친구와 나눠요"
            }
        }

        /* 전부 현재 기능의 사실이다. 여기 문장을 고치기 전에 그 기능이 실제로 그런지 먼저
         * 확인할 것 — 이 화면이 앱보다 앞서 말하기 시작하면 §3.5를 미뤄 온 이유가 되살아난다. */
        var message: String {
            switch self {
            case .shoot: return "가운데 버튼으로 촬영을 시작해요.\n연속 촬영이나 한 장씩 — 템플릿에 따라\n한 컷부터 여섯 컷까지 담을 수 있어요"
            case .compose: return "배치·프레임·보정을 고르고 캡션을 남겨요.\n다 못 끝냈어도 괜찮아요 — 찍어 둔 컷은\n24시간 안에 이어서 완성할 수 있어요"
            case .share: return "공개 범위를 정해 올리고,\n친구의 컷에는 반응과 댓글을 남겨요.\n대표 컷을 고르면 프로필 맨 위에 고정돼요"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if onStart != nil {
                HStack {
                    Spacer()
                    /* 건너뛰기 — 캐러셀을 다 넘겨야만 들어갈 수 있으면 안내가 관문이 된다.
                     * 재열람(도움말)에서는 뒤로 가기가 있어 이 버튼이 필요 없다. */
                    Button("건너뛰기") { finish() }
                        .font(Typography.chip)
                        .foregroundStyle(palette.textSecondary)
                }
                .padding(.horizontal, Spacing.x5)
                .padding(.top, Spacing.x4)
            }

            TabView(selection: $page) {
                ForEach(Tip.allCases, id: \.rawValue) { tip in
                    card(tip).tag(tip.rawValue)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            /* 페이지 점은 직접 그린다 — 시스템 점은 캡슐 배경이 CTA 위에 떠 보였고, 켜진 점의
             * 색을 웜 포인트로 맞출 수 없다. */
            HStack(spacing: Spacing.x2) {
                ForEach(Tip.allCases, id: \.rawValue) { tip in
                    Capsule()
                        .fill(tip.rawValue == page ? palette.brand : palette.borderStrong)
                        .frame(width: tip.rawValue == page ? 20 : 6, height: 6)
                }
            }
            .animation(Motion.standard, value: page)
            .padding(.bottom, Spacing.x6)

            Button(action: advance) {
                Text(buttonLabel).primaryGlassLabel()
            }
            .primaryGlassButton(tint: palette.accent)
            .padding(.horizontal, Spacing.x6)
            .padding(.bottom, Spacing.x8)
        }
        .background(palette.bg)
        .navigationTitle(onStart == nil ? "도움말" : "")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var isLastPage: Bool { page == Tip.allCases.count - 1 }

    /// 마지막 장 전에는 다음 장으로, 마지막 장에서 끝난다 — 명세의 "마지막에 시작하기"다.
    private var buttonLabel: String {
        if !isLastPage { return "다음" }
        return onStart == nil ? "확인" : "시작하기"
    }

    private func advance() {
        if isLastPage {
            finish()
        } else {
            withAnimation { page += 1 }
        }
    }

    private func finish() {
        if let onStart {
            onStart()
        } else {
            dismiss()
        }
    }

    private func card(_ tip: Tip) -> some View {
        VStack(spacing: Spacing.x6) {
            Spacer(minLength: 0)
            illustration(tip)
                .frame(height: 260)
            VStack(spacing: Spacing.x3) {
                Text(tip.title)
                    .font(Typography.title)
                    .foregroundStyle(palette.textPrimary)
                Text(tip.message)
                    .font(Typography.body)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.x6)
    }

    /* 그림은 **앱의 실제 부품**으로 그린다 — 스트립(`StripArt`)·칩(`CutinChip`)·아바타(`AvatarView`).
     * SF Symbol 하나를 원 안에 넣던 0.3.0은 세 장이 구분되지 않았다(0.4.0 감사 G5). 부품으로
     * 그리면 들어가서 보는 것과 같은 모양이라 설명이 곧 예고편이 된다. */
    @ViewBuilder
    private func illustration(_ tip: Tip) -> some View {
        switch tip {
        case .shoot:
            // 찍는 중 — 네 칸 중 두 칸이 찼고, 셔터 링이 옆에 있다
            ZStack {
                StripArt(layout: .strip4, skin: .white, width: 92, filled: 2)
                    .rotationEffect(.degrees(-5))
                    .offset(x: -44)
                    .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
                Circle()
                    .strokeBorder(palette.textPrimary, lineWidth: 3)
                    .frame(width: 64, height: 64)
                    .overlay { Circle().fill(palette.brand).frame(width: 46, height: 46) }
                    .offset(x: 62, y: 60)
            }
        case .compose:
            // 꾸미는 중 — 그리드 스트립과 프레임 칩 셋, 하나가 켜져 있다
            VStack(spacing: Spacing.x4) {
                StripArt(layout: .grid4, skin: .peach, width: 132)
                    .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
                HStack(spacing: Spacing.x2) {
                    CutinChip(label: "클래식 화이트", selected: false) {}
                    CutinChip(label: "피치", selected: true) {}
                    CutinChip(label: "라벤더", selected: false) {}
                }
                .allowsHitTesting(false)
            }
        case .share:
            // 나누는 중 — 스트립 위로 친구 아바타 셋과 반응 하나
            ZStack {
                StripArt(layout: .strip4, skin: .butter, width: 88)
                    .rotationEffect(.degrees(4))
                    .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
                HStack(spacing: -10) {
                    AvatarView(url: nil, nickname: "민", size: 40)
                    AvatarView(url: nil, nickname: "소", size: 40)
                    AvatarView(url: nil, nickname: "준", size: 40)
                }
                .offset(x: -78, y: -70)
                HStack(spacing: 3) {
                    Text("❤️").font(.system(size: 14))
                    Text("3").font(Typography.chip).foregroundStyle(palette.brandInk)
                }
                .padding(.horizontal, Spacing.x2).padding(.vertical, Spacing.x1)
                .background(palette.brandSoft, in: .capsule)
                .tokenBorder(Capsule(), color: palette.brand)
                .offset(x: 74, y: 76)
            }
        }
    }
}

#Preview("팁 — 게이트") {
    TipsView(onStart: {})
        .environment(\.palette, Palette.light)
}

#Preview("팁 — 재열람") {
    NavigationStack {
        TipsView(onStart: nil)
    }
    .environment(\.palette, Palette.dark)
}
