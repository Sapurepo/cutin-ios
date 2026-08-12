/* 템플릿·필터 선택 + 합성 미리보기 + 저장.
 * 원본 RN판은 template/filter/edit 3화면으로 나뉘어 있으나, 스파이크는 화면 수를 늘리지 않기 위해
 * 한 화면에 합친다.
 *
 * 프리뷰도 SwiftUI 뷰 트리가 아니라 **실제 합성기(CutCompositor)를 낮은 해상도로 돌려** 그린다.
 * Core Image 합성이 인터랙티브하게 쓸 만큼 빠른지가 이 스파이크의 검증 대상이기 때문이다. */

import SwiftUI

struct ComposeView: View {
    let cuts: [UIImage]
    let count: CutCount
    let onSaved: () -> Void

    @Environment(FeedStore.self) private var store
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var template: CaptureTemplate = Templates.all[0]
    @State private var filter: FilterID = .original
    @State private var caption = ""
    @State private var preview: UIImage?
    @State private var isRendering = false
    @State private var isSaving = false
    @State private var saveFailed = false

    private static let previewWidth: CGFloat = 540

    private var availableTemplates: [CaptureTemplate] {
        Templates.forCount(count)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.x5) {
                previewPane
                templateStrip
                filterStrip
                captionField
                if saveFailed { saveFailureNotice }
            }
            .padding(.horizontal, Spacing.x4)
            .padding(.bottom, Spacing.x12)
        }
        .background(palette.bg)
        .navigationTitle("꾸미기")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("저장", action: save)
                    .disabled(isSaving || cuts.isEmpty)
            }
        }
        .task(id: renderKey) { await renderPreview() }
        .onAppear {
            if !availableTemplates.contains(template) {
                template = availableTemplates.first ?? Templates.all[0]
            }
        }
    }

    /// 프리뷰 재렌더 트리거 — 템플릿·필터가 바뀔 때만 다시 굽는다.
    private var renderKey: String { "\(template.id)-\(filter.rawValue)" }

    /* 저장 실패를 화면에 남긴다. 실패해도 화면이 그대로면 사용자는 저장 버튼이 죽은 줄 알고
     * 닫기를 누르고, 그러면 찍은 컷이 사라진다. 문구·재시도 다듬기는 편집 3단계 브랜치 몫. */
    private var saveFailureNotice: some View {
        Text("저장하지 못했어요. 저장 공간을 확인하고 다시 시도해 주세요")
            .font(Typography.caption)
            .foregroundStyle(palette.danger)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 미리보기

    private var previewPane: some View {
        ZStack {
            if let preview {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFit()
                    .clipShape(.rect(cornerRadius: Radius.md))
            } else {
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(palette.surfaceSunken)
                    .aspectRatio(1, contentMode: .fit)
            }

            if isRendering {
                ProgressView().tint(palette.textSecondary)
            }
        }
        .animation(.easeOut(duration: Duration.fast), value: preview)
    }

    // MARK: - 템플릿 / 필터 스트립

    private var templateStrip: some View {
        section("템플릿") {
            ForEach(availableTemplates) { item in
                CutinChip(label: item.name, selected: item.id == template.id) {
                    template = item
                }
            }
        }
    }

    private var filterStrip: some View {
        section("보정") {
            ForEach(FilterID.allCases) { item in
                CutinChip(label: item.displayName, selected: item == filter) {
                    filter = item
                }
            }
        }
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.x2) {
            Text(title)
                .font(Typography.caption)
                .foregroundStyle(palette.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.x2) { content() }
            }
            .scrollClipDisabled()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var captionField: some View {
        VStack(alignment: .leading, spacing: Spacing.x2) {
            Text("캡션")
                .font(Typography.caption)
                .foregroundStyle(palette.textSecondary)
            TextField("한 줄 남기기", text: $caption, axis: .vertical)
                .font(Typography.bodyText)
                .lineLimit(1...3)
                .padding(Spacing.x3)
                .background(palette.surface, in: .rect(cornerRadius: Radius.sm))
                .tokenBorder(RoundedRectangle(cornerRadius: Radius.sm), color: palette.border)
        }
    }

    // MARK: - 합성

    private func request(outputWidth: CGFloat) -> CompositionRequest {
        CompositionRequest(
            images: cuts,
            count: count,
            layout: template.layout,
            skin: template.frame,
            filter: filter,
            stampDate: Date(),
            outputWidth: outputWidth
        )
    }

    private func renderPreview() async {
        guard !cuts.isEmpty else { return }
        isRendering = true
        defer { isRendering = false }

        let req = request(outputWidth: Self.previewWidth)
        let rendered = await Task.detached(priority: .userInitiated) {
            CutCompositor.render(req)
        }.value

        guard !Task.isCancelled else { return }
        preview = rendered
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        saveFailed = false

        let req = request(outputWidth: 1080)
        Task {
            let baked = await Task.detached(priority: .userInitiated) {
                CutCompositor.render(req)
            }.value

            do {
                try store.save(
                    image: baked,
                    count: count,
                    layout: template.layout,
                    frameID: template.frame?.id,
                    filterID: filter,
                    caption: caption
                )
                onSaved()
            } catch {
                // 실패했는데 피드로 넘어가면 사용자는 저장됐다고 믿는다.
                saveFailed = true
            }
            isSaving = false
        }
    }
}
