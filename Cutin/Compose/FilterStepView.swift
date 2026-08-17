/* 편집 2단계 — 보정 선택 (명세 §6.2). 원본 `apps/mobile/src/app/capture/filter.tsx` 대응.
 * 뒤로 넘겨 템플릿을 바꿨다 와도 여기서 고른 보정이 남는다 — 선택은 화면이 아니라 플로우가 갖는다.
 *
 * 칩에 이름만 있던 0.3.0은 "필름"이 어떤 색인지 눌러 봐야 알았다(0.4.0 감사). 첫 컷을 작게
 * 줄여 보정마다 한 장씩 미리 보여준다 — 실제 합성과 같은 매트릭스(`ImageFilterer`)라 미리보기와
 * 결과가 같다. 썸네일은 컷이 바뀔 때만 다시 만든다(`cutsRevision`). */

import SwiftUI

struct FilterStepView: View {
    @Bindable var flow: CaptureFlow
    let onNext: () -> Void

    @Environment(\.palette) private var palette

    /// 보정별 미리보기 — 첫 컷을 112px로 줄여 매트릭스를 적용한 것.
    @State private var previews: [FilterID: UIImage] = [:]

    private static let previewPixel: CGFloat = 112
    private static let tile: CGFloat = 60

    var body: some View {
        VStack(spacing: Spacing.x5) {
            ComposePreview(flow: flow)

            VStack(alignment: .leading, spacing: Spacing.x2) {
                Text("보정")
                    .font(Typography.label)
                    .foregroundStyle(palette.textSecondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.x3) {
                        ForEach(FilterID.allCases) { item in
                            tile(item)
                        }
                    }
                }
                .scrollClipDisabled()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

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
        .editStepTitle("보정", step: 2)
        .task(id: flow.cutsRevision) { await renderPreviews() }
    }

    /* 타일 하나 — 미리보기 위에 이름. 켜진 것은 잉크 테두리 + 굵은 이름(칩과 같은 규칙). */
    private func tile(_ item: FilterID) -> some View {
        let selected = item == flow.filterID
        return Button {
            flow.filterID = item
        } label: {
            VStack(spacing: Spacing.x1) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.sm).fill(palette.surfaceSunken)
                    if let image = previews[item] {
                        Image(uiImage: image).resizable().scaledToFill()
                    }
                }
                .frame(width: Self.tile, height: Self.tile)
                .clipShape(.rect(cornerRadius: Radius.sm))
                .tokenBorder(RoundedRectangle(cornerRadius: Radius.sm),
                             color: selected ? palette.brand : palette.border,
                             lineWidth: selected ? 2 : 1)
                Text(item.displayName)
                    .font(selected ? Typography.font(.body, .semibold, size: 12) : Typography.chip)
                    .foregroundStyle(selected ? palette.brandInk : palette.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.displayName)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    /* 첫 컷 한 장을 작게 줄여 일곱 번 매트릭스를 돌린다 — 메인 액터 밖에서. 컷이 없으면(재촬영
     * 중 등) 자리색만 남는다. */
    private func renderPreviews() async {
        guard let first = flow.cuts.first else { previews = [:]; return }
        let pixel = Self.previewPixel
        let rendered = await Task.detached(priority: .userInitiated) {
            // 한 번 줄이고 일곱 번 매트릭스 — 원본(12MP)을 일곱 번 다루지 않는다.
            let small = Self.thumbnail(of: first, pixel: pixel)
            var result: [FilterID: UIImage] = [:]
            for id in FilterID.allCases {
                result[id] = ImageFilterer.apply(id, to: small)
            }
            return result
        }.value
        previews = rendered
    }

    /// 짧은 변이 `pixel`이 되도록 가운데를 정사각으로 잘라 줄인다 — 타일이 정사각이다.
    nonisolated private static func thumbnail(of image: UIImage, pixel: CGFloat) -> UIImage {
        let side = min(image.size.width, image.size.height)
        let scale = pixel / side
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: pixel, height: pixel), format: format).image { _ in
            image.draw(in: CGRect(x: (pixel - drawSize.width) / 2, y: (pixel - drawSize.height) / 2,
                                  width: drawSize.width, height: drawSize.height))
        }
    }
}
