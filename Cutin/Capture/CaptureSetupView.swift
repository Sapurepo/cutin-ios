/* 컷 수 · 촬영 방식 선택 — 명세 §5.1 / §5.2.
 * 원본 `apps/mobile/src/app/capture/count.tsx`(135행)에 대응한다.
 *
 * 0.1.0과 달리 **고를 수 있는 컷 수가 서버 템플릿 목록에서 나온다**(`CutCount` 열거형 삭제).
 * 그래서 목록이 오기 전에는 촬영을 시작할 수 없다 — 컷 수를 정할 수 없고, 정하지 못하면
 * 몇 장을 찍어야 하는지도 모른다. 로컬 기본값(4컷)으로 시작하면 목록이 도착한 뒤 그 수의
 * 템플릿이 없을 수 있어 편집 단계에서 막힌다. */

import SwiftUI

struct CaptureSetupView: View {
    @Bindable var flow: CaptureFlow
    let onStart: () -> Void

    @Environment(TemplateCatalog.self) private var catalog
    @Environment(\.palette) private var palette

    /// nil이면 "아직 안 골랐다" — 목록의 첫 컷 수를 기본으로 쓴다.
    @State private var cutCount: Int?
    @State private var mode: CaptureMode = .burst

    private var activeCutCount: Int? { cutCount ?? catalog.cutCounts.first }

    var body: some View {
        Group {
            if catalog.isReady {
                form
            } else {
                notice
            }
        }
        .padding(Spacing.x4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bg)
        .navigationTitle("촬영")
        .task { await catalog.loadIfNeeded() }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: Spacing.x8) {
            countSection
            modeSection
            Spacer()
            startButton
        }
    }

    /* 목록을 받는 중이거나 실패한 상태. 셸이 시작할 때 이미 한 번 불렀으므로 여기까지 오는 건
     * 대개 실패 후다 — 그래서 다시 시도할 길을 준다. 빈 화면으로 두면 사용자는 앱을 다시 켜는
     * 수밖에 없다. */
    @ViewBuilder
    private var notice: some View {
        if catalog.isLoading {
            ProgressView()
                .tint(palette.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            EmptyStateView(
                title: "템플릿을 불러오지 못했어요",
                message: catalog.failure ?? "잠시 후 다시 시도해주세요",
                systemImage: "square.grid.2x2"
            ) {
                Button("다시 시도") { Task { await catalog.load() } }
                    .primaryGlassButton(tint: palette.accent)
            }
        }
    }

    private var countSection: some View {
        VStack(alignment: .leading, spacing: Spacing.x3) {
            Text("몇 컷을 남길까요?")
                .font(Typography.headline)
                .foregroundStyle(palette.textPrimary)

            HStack(spacing: Spacing.x2) {
                ForEach(catalog.cutCounts, id: \.self) { option in
                    CutinChip(label: "\(option)컷", selected: option == activeCutCount, style: .block) {
                        cutCount = option
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

    /* 여기서 정하는 것은 컷 수지만 플로우에는 **템플릿**을 넘긴다. 컷 수를 따로 들고 있으면
     * 컷 수와 템플릿이 서로 어긋날 수 있는 상태가 생긴다 — 컷 수는 템플릿에서 읽는다.
     * 배치는 편집 1단계에서 같은 컷 수 안에서 바꾼다. */
    private var startButton: some View {
        Button {
            guard let cutCount = activeCutCount,
                  let template = catalog.defaultTemplate(cutCount: cutCount)
            else { return }
            flow.configure(template: template, frame: catalog.defaultFrame, mode: mode)
            onStart()
        } label: {
            Text("촬영 시작").primaryGlassLabel()
        }
        .primaryGlassButton(tint: palette.accent)
        .disabled(activeCutCount == nil)
    }
}
