/* 편집 2단계 — 보정 선택 (명세 §6.2). 원본 `apps/mobile/src/app/capture/filter.tsx` 대응.
 * 뒤로 넘겨 템플릿을 바꿨다 와도 여기서 고른 보정이 남는다 — 선택은 화면이 아니라 플로우가 갖는다. */

import SwiftUI

struct FilterStepView: View {
    @Bindable var flow: CaptureFlow
    let onNext: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: Spacing.x5) {
            ComposePreview(flow: flow)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.x2) {
                    ForEach(FilterID.allCases) { item in
                        CutinChip(label: item.displayName, selected: item == flow.filterID) {
                            flow.filterID = item
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
        .navigationTitle("보정")
        .navigationBarTitleDisplayMode(.inline)
    }
}
