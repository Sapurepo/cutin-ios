/* 편집 1단계 — 템플릿 선택 (명세 §6.1). 원본 `apps/mobile/src/app/capture/template.tsx` 대응.
 * 컷 수에 맞는 템플릿만 보여준다 — 스트립 계열은 4컷 전용이다. */

import SwiftUI

struct TemplateStepView: View {
    @Bindable var flow: CaptureFlow
    let onNext: () -> Void

    @Environment(\.palette) private var palette

    private var available: [CaptureTemplate] { Templates.forCount(flow.count) }

    var body: some View {
        VStack(spacing: Spacing.x5) {
            ComposePreview(flow: flow)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.x2) {
                    ForEach(available) { item in
                        CutinChip(label: item.name, selected: item.id == flow.templateID) {
                            flow.templateID = item.id
                        }
                    }
                }
            }
            .scrollClipDisabled()

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
        .navigationTitle("템플릿")
        .navigationBarTitleDisplayMode(.inline)
    }
}
