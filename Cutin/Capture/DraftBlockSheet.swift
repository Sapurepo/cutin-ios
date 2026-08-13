/* 미완료 촬영 차단 시트 — 명세 §5.3. 원본 `apps/mobile/src/app/capture/draft.tsx` 대응.
 *
 * draft가 1개로 제한되므로(§5.3 확정) 새 촬영을 열려면 이전 것을 끝내거나 버려야 한다.
 * 진행 상태와 첫 컷을 함께 보여준다 — "무엇을 버리는지" 보여주지 않고 폐기를 묻는 것은
 * 사용자에게 눈 감고 고르라는 것이다. */

import SwiftUI

struct DraftBlockSheet: View {
    let draft: DraftStore.Draft
    /// 썸네일은 이 시트가 직접 든다. 셸의 `@State`로 두면 두 번째 표시에서 **이전 draft의**
    /// 첫 컷이 한두 프레임 비친다 — 시트는 표시마다 새로 만들어지므로 여기가 제자리다.
    let loadThumbnail: () async -> UIImage?
    let onResume: () -> Void
    let onDiscard: () -> Void

    @Environment(\.palette) private var palette

    @State private var thumbnail: UIImage?

    var body: some View {
        VStack(spacing: Spacing.x5) {
            header
            progressRow

            VStack(spacing: Spacing.x2) {
                Button(action: onResume) {
                    Text("이어서 작성").primaryGlassLabel()
                }
                .primaryGlassButton(tint: palette.accent)

                Button("폐기하고 새로 시작", role: .destructive, action: onDiscard)
                    .font(Typography.buttonLabel)
                    .padding(.vertical, Spacing.x2)
            }
        }
        .padding(Spacing.x5)
        .presentationDetents([.height(340)])
        .background(palette.bg)
        .task { thumbnail = await loadThumbnail() }
    }

    private var header: some View {
        VStack(spacing: Spacing.x2) {
            Text("진행 중인 촬영이 있어요")
                .font(Typography.headline)
                .foregroundStyle(palette.textPrimary)
            // 명세 §5.3의 문구를 그대로 쓴다.
            Text("이전 포스트 완료 후 생성할 수 있어요")
                .font(Typography.bodyText)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, Spacing.x2)
    }

    private var progressRow: some View {
        HStack(spacing: Spacing.x3) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(palette.surfaceSunken)
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(.rect(cornerRadius: Radius.sm))
            .tokenBorder(RoundedRectangle(cornerRadius: Radius.sm), color: palette.border)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(draft.cutCount) / \(draft.count.rawValue)컷")
                    .font(Typography.numeric)
                    .foregroundStyle(palette.textPrimary)
                Text(draft.createdAt, format: .relative(presentation: .named))
                    .font(Typography.caption)
                    .foregroundStyle(palette.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(Spacing.x3)
        .background(palette.surface, in: .rect(cornerRadius: Radius.md))
        .tokenBorder(RoundedRectangle(cornerRadius: Radius.md), color: palette.border)
    }
}
