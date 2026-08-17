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
                Text(publisher.step.label ?? "저장").primaryGlassLabel()
            }
            .primaryGlassButton(tint: palette.accent)
            .disabled(publisher.isPublishing || flow.cuts.isEmpty)
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

    /* 대표 컷(§6.3). **안 골라도 된다** — 미지정이면 서버가 첫 컷을 기본으로 쓴다.
     * 직접 고른 것과 기본의 구분이 실제 동작을 가른다: 고른 포스트만 프로필 그리드 맨 앞에
     * 고정된다(0.3.0 제품 결정). 그래서 기본 선택을 채워 두지 않고, 고른 것을 다시 누르면
     * 해제된다 — 고정을 무르는 길이 있어야 한다.
     *
     * **첫 컷을 고르면 고정되지 않는다.** 서버가 발행 시 미지정을 0으로 채우므로 "첫 컷 지정"과
     * "미지정"은 서버에서 같은 값이고, 그리드의 `Post.isPinned`도 0을 기본으로 본다. 여기서
     * 고정된다고 말하면 발행 뒤 그리드에 핀이 없어 거짓 약속이 된다 — 문구와 배지를 같은 규칙에서
     * 낸다(`pins`). 서버가 미지정을 null로 남기게 되면(cutin-backend#13) 이 구분은 사라진다. */
    private var thumbnailField: some View {
        VStack(alignment: .leading, spacing: Spacing.x2) {
            Text("대표 컷")
                .font(Typography.caption)
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

    /// 고른 컷이 실제로 고정을 만드는지 — `Post.isPinned`와 같은 규칙(0은 기본).
    private func pins(_ index: Int) -> Bool { index != 0 }

    private var thumbnailHint: String {
        switch flow.thumbnailCutIndex {
        case nil: return "고르면 프로필 맨 위에 고정돼요. 안 고르면 첫 컷이 대표예요"
        case 0?: return "첫 컷은 기본 대표라 고정되지 않아요. 다른 컷을 고르면 고정돼요"
        default: return "이 포스트가 프로필 맨 위에 고정돼요"
        }
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
                             color: selected ? palette.accent : palette.border,
                             lineWidth: selected ? 2 : 1)
                .overlay(alignment: .topTrailing) {
                    if selected && pins(index) {
                        Image(systemName: "pin.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(palette.accent)
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
                .font(Typography.caption)
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
            if await flow.commit(with: publisher, to: store) { onSaved() }
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
