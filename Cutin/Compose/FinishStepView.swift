/* 편집 3단계 — 캡션 + 저장 (명세 §6.4에서 로컬 범위만).
 * 원본 `apps/mobile/src/app/capture/edit.tsx` 대응.
 *
 * 공개 범위 UI는 만들지 않는다 — 저장할 곳도, 로컬에서 의미도 없다(0.2.0).
 * 대표 컷 지정(§6.3)도 여기 두지 않았다: 피드와 상세가 모두 합성 결과를 보여주므로
 * 대표 컷을 읽는 화면이 아직 없다. 3열 그리드가 생기는 프로필 브랜치가 그 소비처다.
 *
 * 저장 자체는 `CaptureFlow.commit(to:)`가 한다 — 진행 상태와 실패가 이 화면보다 오래 살아야
 * 한다. 이 화면은 그 상태를 그리고 문구로 옮기는 일만 한다. */

import SwiftUI

struct FinishStepView: View {
    @Bindable var flow: CaptureFlow
    let onSaved: () -> Void

    @Environment(FeedStore.self) private var store
    @Environment(\.palette) private var palette

    @FocusState private var isCaptionFocused: Bool

    var body: some View {
        VStack(spacing: Spacing.x5) {
            ComposePreview(flow: flow)
            captionField
            if let failure = flow.saveFailure { failureNotice(failure) }

            Spacer(minLength: 0)

            Button(action: save) {
                Text(flow.isSaving ? "저장 중…" : "저장").primaryGlassLabel()
            }
            .primaryGlassButton(tint: palette.accent)
            .disabled(flow.isSaving || flow.cuts.isEmpty)
        }
        .padding(.horizontal, Spacing.x4)
        .padding(.top, Spacing.x4)
        .padding(.bottom, Spacing.x6)
        .background(palette.bg)
        .navigationTitle("마무리")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            /* 캡션은 여러 줄이라 Return이 줄바꿈이다. 키보드를 접을 길이 없으면 사용자는
             * 미리보기도 실패 문구도 보지 못한 채로 남는다. */
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("완료") { isCaptionFocused = false }
            }
        }
    }

    private var captionField: some View {
        VStack(alignment: .leading, spacing: Spacing.x2) {
            Text("캡션")
                .font(Typography.caption)
                .foregroundStyle(palette.textSecondary)
            TextField("한 줄 남기기", text: $flow.caption, axis: .vertical)
                .font(Typography.bodyText)
                .lineLimit(1...3)
                .focused($isCaptionFocused)
                .padding(Spacing.x3)
                .background(palette.surface, in: .rect(cornerRadius: Radius.sm))
                .tokenBorder(RoundedRectangle(cornerRadius: Radius.sm), color: palette.border)
        }
    }

    /* 실패를 화면에 남긴다. 조용히 넘어가면 사용자는 저장 버튼이 죽은 줄 알고 뒤로 나가고,
     * 그러면 찍은 컷이 사라진다. 재시도는 같은 저장 버튼이다 — 실패 후에도 계속 눌린다. */
    private func failureNotice(_ error: Error) -> some View {
        Text(message(for: error))
            .font(Typography.caption)
            .foregroundStyle(palette.danger)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 원인마다 사용자가 할 수 있는 일이 다르다 — 인덱스가 막힌 경우는 공간을 비워도 풀리지 않는다.
    private func message(for error: Error) -> String {
        if case FeedStoreError.indexUnwritable = error {
            return "저장된 목록을 읽지 못해 새 저장을 막아 뒀어요. 앱을 다시 켜면 풀립니다"
        }
        return "저장하지 못했어요. 저장 공간을 확인하고 다시 시도해 주세요"
    }

    private func save() {
        isCaptionFocused = false
        Task {
            if await flow.commit(to: store) { onSaved() }
        }
    }
}
