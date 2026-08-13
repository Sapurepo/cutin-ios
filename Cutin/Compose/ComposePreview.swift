/* 편집 세 단계가 공유하는 미리보기 — 명세 §6.2.
 *
 * SwiftUI 뷰 트리로 흉내내지 않고 **실제 합성기(CutCompositor)를 낮은 해상도로 돌려** 그린다.
 * 화면에서 고른 것과 파일로 남는 것이 다른 파이프라인을 타면, 고를 때 본 그림과 저장된 그림이
 * 어긋나도 아무도 모른다. 저장은 같은 요청을 폭만 키워 다시 굽는다.
 *
 * 세 단계가 각자 미리보기를 그리므로 앞으로 넘길 때마다 한 번씩 다시 굽는다. 합성이
 * 메인 액터 밖에서 100ms대에 끝나므로(compose-pipeline 브랜치 실측) 캐시를 두지 않았다. */

import SwiftUI

struct ComposePreview: View {
    let flow: CaptureFlow

    @Environment(\.palette) private var palette

    @State private var image: UIImage?
    @State private var isRendering = false

    /// 화면용 합성 폭. 저장은 `CutCompositor.saveWidth`로 다시 굽는다.
    private static let width: CGFloat = 540

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(.rect(cornerRadius: Radius.md))
            } else {
                // 로드 전 레이아웃이 튀지 않게 정사각으로 자리를 잡는다 (템플릿 대부분이 1:1).
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(palette.surfaceSunken)
                    .aspectRatio(1, contentMode: .fit)
            }

            if isRendering {
                ProgressView().tint(palette.textSecondary)
            }
        }
        .animation(.easeOut(duration: Duration.fast), value: image)
        .task(id: renderKey) { await render() }
    }

    /* 다시 구워야 하는 입력이 바뀌었는지. `cutsRevision`이 없으면 카메라로 돌아가
     * 한 컷을 재촬영하고 와도 컷 수가 같아 옛 그림이 남는다.
     *
     * 배치와 외형이 따로 오므로(`/templates`·`/frames`) 둘을 모두 센다 — 프레임만 바꿔도
     * 색과 여백이 달라진다. */
    private var renderKey: String {
        let template = flow.template?.id.uuidString ?? "-"
        let frame = flow.frame?.id.uuidString ?? "-"
        return "\(template)-\(frame)-\(flow.filterID.rawValue)-\(flow.cutsRevision)"
    }

    private func render() async {
        guard !flow.cuts.isEmpty else { return }
        // 템플릿·프레임이 없으면 그릴 배치가 없다. 자리만 잡아 둔 사각형이 그대로 남는다.
        guard let request = flow.compositionRequest(outputWidth: Self.width) else { return }

        /* 칩을 빠르게 훑으면 선택마다 렌더가 시작된다. `Task.detached`는 취소를 물려받지 않으니
         * 한 번 시작한 합성은 끝까지 간다 — 컷마다 12MP를 축소하는 일이 겹쳐 쌓인다.
         * `Task.sleep`은 취소되므로, 여기서 걸러 마지막 선택만 굽는다. */
        try? await Task.sleep(for: .milliseconds(80))
        guard !Task.isCancelled else { return }

        isRendering = true

        let rendered = await Task.detached(priority: .userInitiated) {
            CutCompositor.render(request)
        }.value

        /* 취소됐으면 `isRendering`을 건드리지 않고 나간다. defer로 내리면 뒤늦게 끝난 옛 렌더가
         * 새 렌더의 깃발을 끄고, 그러면 합성이 도는 중에 스피너가 사라진다. */
        guard !Task.isCancelled else { return }
        image = rendered
        isRendering = false
    }
}
