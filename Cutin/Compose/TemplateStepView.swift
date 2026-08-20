/* 편집 1단계 — 템플릿 선택 (명세 §6.1). 원본 `apps/mobile/src/app/capture/template.tsx` 대응.
 *
 * 0.1.0의 "템플릿"은 배치와 프레임 색을 한 덩어리로 묶은 로컬 상수였다(`CaptureTemplate`이
 * `layout`과 `frame`을 함께 들었다). 서버는 이 둘을 **따로 소유한다** — `/templates`는 배치,
 * `/frames`는 외형. 그래서 칩도 두 줄로 갈린다. 조합을 다시 묶어 한 줄로 보여주면
 * 8 × 8 = 64개 칩이 되고, 서버가 어느 쪽을 늘려도 그 곱이 커진다.
 *
 * 배치는 **찍은 컷 수와 같은 것만** 보여준다 — 스트립 계열은 4컷 전용이다. */

import SwiftUI

struct TemplateStepView: View {
    @Bindable var flow: CaptureFlow
    let onNext: () -> Void

    @Environment(TemplateCatalog.self) private var catalog
    @Environment(\.palette) private var palette

    private var layouts: [Template] { catalog.templates(cutCount: flow.cutCount) }

    var body: some View {
        VStack(spacing: Spacing.x5) {
            ComposePreview(flow: flow)

            /* 배치가 하나뿐이면 칩 줄을 만들지 않는다 — 고를 것이 없는 줄은 누를 수 있는 것처럼
             * 보이기만 한다. 컷 수에 따라 실제로 그런 경우가 있다(한 컷). */
            if layouts.count > 1 {
                chips(title: "배치") {
                    ForEach(layouts, id: \.id) { item in
                        let selected = item.id == flow.template?.id
                        // 이름 앞에 배치 글리프 — 어떤 모양인지 눌러 보지 않고도 안다.
                        Button {
                            flow.select(template: item)
                        } label: {
                            HStack(spacing: Spacing.x2) {
                                TemplateGlyph(template: item, height: 16, selected: selected)
                                Text(item.name)
                                    .font(selected ? Typography.font(.body, .semibold, size: 12) : Typography.chip)
                                    .foregroundStyle(selected ? palette.brandInk : palette.textPrimary)
                            }
                            .padding(.horizontal, Spacing.x3)
                            .padding(.vertical, Spacing.x2)
                            .background(selected ? palette.brandSoft : palette.surface, in: .capsule)
                            .tokenBorder(Capsule(), color: selected ? palette.brand : palette.border)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            chips(title: "프레임") {
                ForEach(catalog.frames, id: \.id) { item in
                    CutinChip(label: item.name, selected: item.id == flow.frame?.id) {
                        flow.frame = item
                    }
                }
            }

            Spacer(minLength: 0)

            Button(action: onNext) {
                Text("다음").primaryGlassLabel()
            }
            .primaryGlassButton(tint: palette.accent)
        }
        .padding(.horizontal, Spacing.x4)
        .padding(.top, Spacing.x4)
        .padding(.bottom, Spacing.x6)
        .background(palette.bg)
        .editStepTitle("템플릿", step: 1)
    }

    private func chips<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.x2) {
            Text(title)
                .font(Typography.label)
                .foregroundStyle(palette.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.x2) { content() }
            }
            .scrollClipDisabled()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
