/* 편집 3단계 — 캡션 · 공개 범위 · 발행 (명세 §6.4).
 *
 * **공개 범위를 여기서 만든다.** 0.1.0에는 저장할 곳도 의미도 없어 미뤘는데, 이제 서버가
 * `visibility`를 갖고 피드 노출이 그 값에 달려 있다.
 *
 * 대표 컷 지정(§6.3)은 여전히 두지 않았다. 서버에 `thumbnailCutIndex`가 있지만 **읽는 화면이
 * 없다** — 피드·상세·프로필 그리드가 모두 합성 결과를 보여준다. 소비처가 생길 때 만든다.
 *
 * 발행 자체는 `CaptureFlow.commit`이 한다 — 진행 상태와 실패가 이 화면보다 오래 살아야 한다.
 * 왕복이 컷 수에 따라 열여섯 번쯤이라 진행 단계도 함께 그린다. */

import SwiftUI

struct FinishStepView: View {
    @Bindable var flow: CaptureFlow
    let onSaved: () -> Void

    @Environment(PostStore.self) private var store
    @Environment(PostPublisher.self) private var publisher
    @Environment(\.palette) private var palette

    @FocusState private var isCaptionFocused: Bool

    var body: some View {
        VStack(spacing: Spacing.x5) {
            ComposePreview(flow: flow)
            captionField
            thumbnailField
            visibilityField
            if let failure = flow.saveFailure { failureNotice(failure) }

            Spacer(minLength: 0)

            Button(action: save) {
                // "저장"이 아니라 "올리기" — 이 버튼은 서버에 발행한다(0.4.0 감사).
                Text(publisher.step.label ?? "올리기").primaryGlassLabel()
            }
            .primaryGlassButton(tint: palette.accent)
            .disabled(publisher.isPublishing || flow.cuts.isEmpty)
        }
        .padding(.horizontal, Spacing.x4)
        .padding(.top, Spacing.x4)
        .padding(.bottom, Spacing.x6)
        .background(palette.bg)
        .editStepTitle("마무리", step: 3)
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
                .font(Typography.label)
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

    /* 대표 컷(§6.3). **안 골라도 된다** — 미지정이면 서버가 첫 컷을 기본으로 쓴다.
     * 직접 고른 것과 기본의 구분이 실제 동작을 가른다: 고른 포스트만 프로필 그리드 맨 앞에
     * 고정된다(0.3.0 제품 결정). 그래서 기본 선택을 채워 두지 않고, 고른 것을 다시 누르면
     * 해제된다 — 고정을 무르는 길이 있어야 한다.
     *
     * 고정은 발행 요청의 `pinned`로 따로 실린다(cutin-backend#14) — 첫 컷을 골라도 고정이다.
     * (그 전 서버에서는 첫 컷 지정이 미지정과 같아 고정되지 않았다. 문구와 배지는 같은 규칙에서 낸다.) */
    private var thumbnailField: some View {
        VStack(alignment: .leading, spacing: Spacing.x2) {
            Text("대표 컷")
                .font(Typography.label)
                .foregroundStyle(palette.textSecondary)
            HStack(spacing: Spacing.x2) {
                ForEach(Array(flow.cuts.enumerated()), id: \.offset) { index, cut in
                    thumbnailChoice(index: index, cut: cut)
                }
            }
            Text(thumbnailHint)
                .font(Typography.caption)
                .foregroundStyle(palette.textSecondary)
        }
    }

    private var thumbnailHint: String {
        flow.thumbnailCutIndex == nil
            ? "고르면 프로필 맨 위에 고정돼요. 안 고르면 첫 컷이 대표예요"
            : "이 포스트가 프로필 맨 위에 고정돼요"
    }

    private func thumbnailChoice(index: Int, cut: UIImage) -> some View {
        let selected = flow.thumbnailCutIndex == index
        return Button {
            flow.thumbnailCutIndex = selected ? nil : index
        } label: {
            Image(uiImage: cut)
                .resizable()
                .scaledToFill()
                .frame(width: 52, height: 52)
                .clipShape(.rect(cornerRadius: Radius.sm))
                .tokenBorder(RoundedRectangle(cornerRadius: Radius.sm),
                             color: selected ? palette.brand : palette.border,
                             lineWidth: selected ? 2 : 1)
                .overlay(alignment: .topTrailing) {
                    // 고른 컷에 핀 — 어느 컷이든 고르면 고정이다(발행 요청의 `pinned`).
                    if selected {
                        Image(systemName: "pin.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(palette.brand)
                            .background(palette.bg, in: .circle)
                            .offset(x: 4, y: -4)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private var visibilityField: some View {
        VStack(alignment: .leading, spacing: Spacing.x2) {
            Text("공개 범위")
                .font(Typography.label)
                .foregroundStyle(palette.textSecondary)
            HStack(spacing: Spacing.x2) {
                ForEach(PostVisibility.allCases, id: \.self) { option in
                    CutinChip(label: option.label, selected: option == flow.visibility,
                              style: .block) {
                        flow.visibility = option
                    }
                }
            }
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

    /* 서버가 준 문구를 그대로 쓴다 — 거절 이유(컷이 모자람·합성본 미완료·템플릿 없음)를
     * 앱이 다시 쓰면 서버가 조건을 바꿔도 화면은 옛 문장을 말한다. */
    private func message(for error: Error) -> String {
        if let api = error as? APIError {
            if case .transport = api { return "서버에 연결할 수 없어요. 잠시 후 다시 시도해주세요" }
            return api.serverMessage ?? "저장하지 못했어요. 잠시 후 다시 시도해주세요"
        }
        return (error as? LocalizedError)?.errorDescription
            ?? "저장하지 못했어요. 잠시 후 다시 시도해주세요"
    }

    private func save() {
        isCaptionFocused = false
        Task {
            if await flow.commit(with: publisher, to: store) {
                Haptics.success()   // 올라갔다 — 화면이 바로 닫히므로 손끝이 알려 준다
                SoundEffects.success()
                onSaved()
            }
        }
    }
}

extension PostVisibility {
    var label: String {
        switch self {
        case .friends: return "친구"
        case .public: return "전체"
        case .private: return "나만"
        }
    }
}
