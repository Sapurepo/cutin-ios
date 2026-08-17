/* 디자인 카탈로그 — 토큰과 부품을 한 화면에 늘어놓는다. **Debug 빌드에만 있다.**
 *
 * 디자이너가 없는 프로젝트에서 이 화면이 Figma를 대신한다(`Design/README.md` 원칙 3). 부품을
 * 고칠 때 여기서 라이트/다크·Dynamic Type을 한 번에 보고, 화면은 그 부품을 가져다 쓴다.
 * 여는 곳: 프로필 톱니 메뉴의 "디자인 카탈로그" · 감사 도구의 `AUDIT_SCREEN=catalog`.
 *
 * 여기 나오는 것만이 규칙이다 — 화면이 카탈로그에 없는 색·크기를 쓰기 시작하면 카탈로그부터 늘린다. */

#if DEBUG
import SwiftUI

struct DesignCatalogView: View {
    @Environment(\.palette) private var palette
    @State private var chip = "네 컷"
    @State private var reaction: ReactionType? = .love

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.x8) {
                    colors.id("colors")
                    typography.id("typography")
                    chips.id("chips")
                    buttons.id("buttons")
                    surfaces.id("surfaces")
                    images.id("images")
                    emptyState.id("empty")
                }
                .padding(Spacing.x4)
                .padding(.bottom, Spacing.x8)
            }
            // 감사 도구가 절 하나를 바로 찍을 수 있게 — `AUDIT_SECTION=buttons`
            .onAppear {
                if let section = ProcessInfo.processInfo.environment["AUDIT_SECTION"], !section.isEmpty {
                    proxy.scrollTo(section, anchor: .top)
                }
            }
        }
        .background(palette.bg)
        .navigationTitle("디자인 카탈로그")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 색

    private var colors: some View {
        section("색 — 크롬은 잉크, 켜진 것만 웜") {
            let swatches: [(String, Color, Bool)] = [
                ("bg", palette.bg, true), ("surface", palette.surface, true),
                ("sunken", palette.surfaceSunken, true), ("raised", palette.surfaceRaised, true),
                ("border", palette.border, false), ("borderStrong", palette.borderStrong, false),
                ("textPrimary", palette.textPrimary, false), ("textSecondary", palette.textSecondary, false),
                ("accent", palette.accent, false), ("danger", palette.danger, false),
                ("brand", palette.brand, false), ("brandInk", palette.brandInk, false),
                ("brandSoft", palette.brandSoft, true),
            ]
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.x2), count: 4),
                      spacing: Spacing.x3) {
                ForEach(swatches, id: \.0) { name, color, bordered in
                    VStack(spacing: Spacing.x1) {
                        RoundedRectangle(cornerRadius: Radius.sm)
                            .fill(color)
                            .frame(height: 44)
                            .overlay {
                                if bordered {
                                    RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(palette.border)
                                }
                            }
                        Text(name).font(Typography.caption).foregroundStyle(palette.textSecondary)
                    }
                }
            }
        }
    }

    // MARK: - 타이포

    private var typography: some View {
        section("타이포 — 열 단계, 임의 크기 없음") {
            VStack(alignment: .leading, spacing: Spacing.x2) {
                sample("largeTitle 28 bold", Typography.largeTitle)
                sample("title 22 semibold", Typography.title)
                sample("headline 17 semibold", Typography.headline)
                sample("subheadline 15 semibold", Typography.subheadline)
                sample("body 15 — 오늘 남긴 컷, 친구가 본다", Typography.body)
                sample("bodyText 14 (옮겨 가는 중)", Typography.bodyText)
                sample("label 13 medium — 배치 · 공개 범위", Typography.label)
                sample("caption 11", Typography.caption)
                sample("chip 12 medium", Typography.chip)
                sample("buttonLabel 15 semibold", Typography.buttonLabel)
                HStack(spacing: Spacing.x3) {
                    Text("2026.08.17 · 12:41").font(Typography.numeric)
                    Text("CUTIN").font(Typography.logo(size: 22)).kerning(22 * Typography.logoKerning)
                }
                .foregroundStyle(palette.textPrimary)
                Text("numeric 15 Geist · logo Geist bold").font(Typography.caption).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private func sample(_ text: String, _ font: Font) -> some View {
        Text(text).font(font).foregroundStyle(palette.textPrimary)
    }

    // MARK: - 칩

    private var chips: some View {
        section("칩 — 켜진 것은 웜 옅은 면, 채움 없음") {
            VStack(alignment: .leading, spacing: Spacing.x3) {
                HStack(spacing: Spacing.x2) {
                    ForEach(["한 컷", "두 컷", "네 컷", "여섯 컷"], id: \.self) { name in
                        CutinChip(label: name, selected: chip == name, style: .block) { chip = name }
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.x2) {
                        ForEach(["원본", "흑백", "소프트", "웜", "쿨", "필름", "세피아"], id: \.self) { name in
                            CutinChip(label: name, selected: name == "필름") {}
                        }
                    }
                }
                .scrollClipDisabled()
                reactions
            }
        }
    }

    /// 상세 화면의 반응 줄과 같은 규칙 — 내 반응이 켜진 것이다.
    private var reactions: some View {
        HStack(spacing: Spacing.x2) {
            ForEach(ReactionType.allCases, id: \.self) { type in
                let mine = reaction == type
                Button { reaction = mine ? nil : type } label: {
                    HStack(spacing: 2) {
                        Text(type.emoji)
                        Text("3").font(Typography.chip)
                            .foregroundStyle(mine ? palette.brandInk : palette.textSecondary)
                    }
                    .padding(.horizontal, Spacing.x2).padding(.vertical, Spacing.x1)
                    .background(mine ? palette.brandSoft : palette.surface, in: .capsule)
                    .tokenBorder(Capsule(), color: mine ? palette.brand : palette.border)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 버튼

    private var buttons: some View {
        section("버튼 — CTA만 잉크 채움, 나머지는 글래스") {
            VStack(spacing: Spacing.x3) {
                Button {} label: { Text("촬영 시작").primaryGlassLabel() }
                    .primaryGlassButton(tint: palette.accent)
                Button {} label: { Text("팔로잉").glassLabel() }
                    .buttonStyle(.glass)
                HStack(spacing: Spacing.x3) {
                    // 제목만 넘기는 채움 CTA — 라벨 수정자 없이도 글자가 보여야 한다
                    Button("다시 시도") {}.primaryGlassButton(tint: palette.accent)
                    Button("허용") {}.primaryGlassButton(tint: .white, label: Palette.light.accent)
                        .padding(Spacing.x2).background(Color.black, in: .rect(cornerRadius: Radius.sm))
                    Button("삭제", role: .destructive) {}.buttonStyle(.glass)
                    Spacer()
                    Image(systemName: "bell")
                        .overlay(alignment: .topTrailing) {
                            Circle().fill(palette.brand).frame(width: 8, height: 8).offset(x: 4, y: -2)
                        }
                        .foregroundStyle(palette.textPrimary)
                }
            }
        }
    }

    // MARK: - 표면

    private var surfaces: some View {
        section("표면 — 카드는 raised(라이트 그림자 · 다크 한 단 밝음)") {
            VStack(alignment: .leading, spacing: Spacing.x2) {
                RoundedRectangle(cornerRadius: Radius.md).fill(palette.surfaceSunken)
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .overlay { Shimmer().clipShape(.rect(cornerRadius: Radius.md)) }
                HStack(spacing: Spacing.x2) {
                    AvatarView(url: nil, nickname: "네컷러버", size: 26)
                    Text("네컷러버").font(Typography.subheadline).foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text("2026년 8월 17일").font(Typography.caption).foregroundStyle(palette.textSecondary)
                }
                Text("카드 하나의 골격 — 이미지 · 작성자 행 · 캡션").font(Typography.body)
                    .foregroundStyle(palette.textPrimary)
            }
            .padding(Spacing.x3)
            .raised()
        }
    }

    // MARK: - 이미지

    private var images: some View {
        section("이미지 — 자리색 위에 반짝임, 도착하면 페이드") {
            HStack(spacing: Spacing.x2) {
                RemoteImage(url: nil).frame(width: 96, height: 96).clipShape(.rect(cornerRadius: Radius.md))
                RemoteImage(url: nil).frame(width: 96, height: 96).clipShape(.rect(cornerRadius: Radius.md))
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "pin.fill").font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white).padding(4).background(palette.brand, in: .circle).padding(4)
                    }
                AvatarView(url: nil, nickname: "Ada", size: 56)
                AvatarView(url: nil, nickname: nil, size: 40)
            }
        }
    }

    // MARK: - 빈 상태

    private var emptyState: some View {
        section("빈 상태") {
            EmptyStateView(title: "보관한 컷이 없어요", message: "포스트를 열어 보관을 누르면 여기 모여요",
                           systemImage: "bookmark")
                .frame(height: 220)
        }
    }

    // MARK: - 보조

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.x3) {
            Text(title).font(Typography.label).foregroundStyle(palette.textSecondary)
            content()
        }
    }
}

#Preview("DesignCatalog") {
    NavigationStack { DesignCatalogView() }
        .environment(\.palette, Palette.light)
}
#endif
