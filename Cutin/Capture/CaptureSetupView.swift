/* 컷 수 · 촬영 방식 선택 — 명세 §5.1 / §5.2.
 * 원본 `apps/mobile/src/app/capture/count.tsx`(135행)에 대응한다. */

import SwiftUI

struct CaptureSetupView: View {
    @Bindable var flow: CaptureFlow
    let onStart: () -> Void

    @Environment(\.palette) private var palette

    @State private var count: CutCount = .four
    @State private var mode: CaptureMode = .burst

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.x8) {
            countSection
            modeSection
            Spacer()
            startButton
        }
        .padding(Spacing.x4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bg)
        .navigationTitle("촬영")
    }

    private var countSection: some View {
        VStack(alignment: .leading, spacing: Spacing.x3) {
            Text("몇 컷을 남길까요?")
                .font(Typography.headline)
                .foregroundStyle(palette.textPrimary)

            HStack(spacing: Spacing.x2) {
                ForEach(CutCount.allCases) { option in
                    CutinChip(label: option.label, selected: option == count, style: .block) {
                        count = option
                    }
                }
            }
        }
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: Spacing.x3) {
            Text("어떻게 찍을까요?")
                .font(Typography.headline)
                .foregroundStyle(palette.textPrimary)

            VStack(spacing: Spacing.x2) {
                ForEach(CaptureMode.allCases) { option in
                    Button {
                        mode = option
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.label)
                                    .font(Typography.buttonLabel)
                                    .foregroundStyle(palette.textPrimary)
                                Text(option.hint)
                                    .font(Typography.caption)
                                    .foregroundStyle(palette.textSecondary)
                            }
                            Spacer()
                            if option == mode {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(palette.textPrimary)
                            }
                        }
                        .padding(Spacing.x4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(palette.surface, in: .rect(cornerRadius: Radius.md))
                        .tokenBorder(RoundedRectangle(cornerRadius: Radius.md),
                                     color: option == mode ? palette.borderStrong : palette.border,
                                     lineWidth: option == mode ? 1.5 : 1)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var startButton: some View {
        Button {
            flow.configure(count: count, mode: mode)
            onStart()
        } label: {
            Text("촬영 시작")
                .font(Typography.buttonLabel)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.x4)
        }
        .primaryGlassButton(tint: palette.accent)
    }
}
