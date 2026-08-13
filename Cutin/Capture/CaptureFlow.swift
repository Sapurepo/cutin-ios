/* 촬영 플로우 상태 — cutin-frontend `apps/mobile/src/stores/captureStore.ts`(zustand) 대체.
 * 컷 수·촬영 방식·촬영된 컷·재촬영 인덱스, 그리고 편집 선택을 촬영·편집 화면이 공유한다. */

import Observation
import UIKit

@MainActor
@Observable
final class CaptureFlow {
    private(set) var count: CutCount = .four
    private(set) var mode: CaptureMode = .burst
    private(set) var cuts: [UIImage] = []
    /// nil이 아니면 "그 인덱스를 다시 찍는 중"
    var retakeIndex: Int?

    /* 편집 선택도 플로우가 갖는다. 편집이 한 화면이던 동안은 ComposeView의 `@State`로 충분했지만,
     * 템플릿·보정·마무리 세 화면으로 나뉘면 뒤로 넘길 때 그 화면의 상태가 사라져 선택이 초기화된다.
     * draft 영속(§5.3)도 이 값들을 파일로 내려야 하므로 소유자는 화면이 아니라 플로우여야 한다. */
    var templateID: String = Templates.all[0].id
    var filterID: FilterID = .original
    var caption = ""

    /* 컷 배열이 몇 번 바뀌었는지. 재촬영은 컷 수를 바꾸지 않고 한 장만 교체하므로,
     * 컷 수만 보는 미리보기는 카메라로 돌아가 다시 찍고 와도 옛 그림을 그대로 둔다. */
    private(set) var cutsRevision = 0

    var template: CaptureTemplate { Templates.find(templateID) }

    var isComplete: Bool { cuts.count >= count.rawValue && retakeIndex == nil }
    /// 다음에 채울 컷의 1-based 번호 (표시용)
    var nextSlot: Int { min(cuts.count + 1, count.rawValue) }

    func configure(count: CutCount, mode: CaptureMode) {
        self.count = count
        self.mode = mode
        reset()
    }

    /// 재촬영 중이면 해당 슬롯을 교체하고, 아니면 뒤에 붙인다.
    func addCut(_ image: UIImage) {
        if let index = retakeIndex, cuts.indices.contains(index) {
            cuts[index] = image
            retakeIndex = nil
        } else if cuts.count < count.rawValue {
            cuts.append(image)
        } else {
            return
        }
        cutsRevision += 1
    }

    func toggleRetake(_ index: Int) {
        retakeIndex = (retakeIndex == index) ? nil : index
    }

    /// 이번 촬영을 버린다 — 컷과 편집 선택을 모두 되돌린다.
    func reset() {
        cuts = []
        retakeIndex = nil
        cutsRevision += 1
        // 컷 수가 바뀌면 이전 템플릿이 그 컷 수를 지원하지 않을 수 있다(스트립 계열은 4컷 전용).
        templateID = Templates.forCount(count).first?.id ?? Templates.all[0].id
        filterID = .original
        caption = ""
    }

    /// 미리보기와 저장이 **같은 입력**을 쓰도록 요청 생성을 한곳에 둔다.
    /// 폭만 다르게 불러 화면용과 파일용을 굽는다.
    func compositionRequest(outputWidth: CGFloat) -> CompositionRequest {
        CompositionRequest(
            images: cuts,
            count: count,
            layout: template.layout,
            skin: template.frame,
            filter: filterID,
            stampDate: Date(),
            outputWidth: outputWidth
        )
    }

    // MARK: - 커밋

    /* 저장 진행 상태를 화면이 아니라 플로우가 갖는다.
     *
     * 마무리 화면의 `@State`로 두면 저장을 누른 뒤 뒤로 갔다 다시 들어올 때 새 화면이
     * 만들어지면서 "저장 중"이 초기화된다. 그 상태에서 다시 누르면 **한 번의 촬영이 두 번
     * 저장돼** JPEG도 포스트도 둘이 된다. 실패 문구도 같은 이유로 죽은 화면에 쓰여 사라진다. */
    private(set) var isSaving = false
    private(set) var saveFailure: Error?

    /// 합성 결과를 파일로 남긴다. 성공하면 true.
    func commit(to store: FeedStore) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        saveFailure = nil
        defer { isSaving = false }

        /* 메타데이터를 **굽기 전에** 붙잡는다. 렌더는 200ms대가 걸리고 그 사이 사용자는
         * 뒤로 가 보정을 바꾸거나 캡션을 더 칠 수 있다. 나중에 읽으면 파일은 옛 선택으로
         * 구워졌는데 인덱스에는 새 선택이 적혀, 목록과 그림이 서로 다른 말을 한다. */
        let request = compositionRequest(outputWidth: CutCompositor.saveWidth)
        let bakedCount = count
        let bakedLayout = template.layout
        let bakedFrameID = template.frame.id
        let bakedFilterID = filterID
        let bakedCaption = caption

        let baked = await Task.detached(priority: .userInitiated) {
            CutCompositor.render(request)
        }.value

        do {
            try store.save(
                image: baked,
                count: bakedCount,
                layout: bakedLayout,
                frameID: bakedFrameID,
                filterID: bakedFilterID,
                caption: bakedCaption
            )
            return true
        } catch {
            // 실패했는데 피드로 넘어가면 사용자는 저장됐다고 믿는다.
            saveFailure = error
            return false
        }
    }
}
