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

    // MARK: - draft (§5.3)

    @ObservationIgnored private let drafts = DraftStore()

    /// 파일로 남아 있는 진행 중인 촬영. 만료된 것은 읽는 시점에 정리되므로 여기까지 오지 않는다.
    private(set) var draft: DraftStore.Draft?

    var hasDraft: Bool { draft != nil }

    init() {
        draft = drafts.load()
    }

    /* 앱이 포그라운드를 떠날 때 셸이 부른다. 컷 JPEG는 촬영 즉시 쓰지만 템플릿·보정·캡션은
     * 입력마다 파일을 건드릴 이유가 없어, 내려가기 직전에 몰아 쓴다. 강제 종료도 백그라운드를
     * 지나므로 이 지점이 마지막 기회다.
     *
     * 알림을 여기서 직접 듣지 않는 이유: 앱 생애주기는 셸의 관심사이고, `@MainActor` 클래스의
     * `deinit`은 Swift 6에서 격리된 옵저버 토큰을 만질 수 없다. */
    func persistDraftMeta() {
        writeDraftMeta()
    }

    func configure(count: CutCount, mode: CaptureMode) {
        self.count = count
        self.mode = mode
        /* 새 촬영은 이전 draft를 지우고 시작한다. 남겨 두면 컷 수가 줄었을 때(4컷 → 2컷)
         * 옛 `cut-2.jpg`가 살아남아 복구가 있지도 않은 컷을 되살린다. */
        discardDraft()
    }

    /// 재촬영 중이면 해당 슬롯을 교체하고, 아니면 뒤에 붙인다.
    func addCut(_ image: UIImage) {
        let slot: Int
        if let index = retakeIndex, cuts.indices.contains(index) {
            cuts[index] = image
            retakeIndex = nil
            slot = index
        } else if cuts.count < count.rawValue {
            cuts.append(image)
            slot = cuts.count - 1
        } else {
            return
        }
        cutsRevision += 1
        persist(image, at: slot)
    }

    func toggleRetake(_ index: Int) {
        retakeIndex = (retakeIndex == index) ? nil : index
    }

    /// 메모리의 진행 상태만 비운다. **파일로 내려간 draft는 남는다** — 촬영을 닫고 나가도
    /// 다음 진입에서 이어 쓸 수 있어야 하고, 그게 §5.3의 전부다.
    func clearMemory() {
        /* 비우기 전에 마지막 선택을 draft에 내린다. 컷 JPEG는 촬영 즉시 쓰지만 템플릿·보정·캡션은
         * 마지막 컷 이후에 고른 것이 남아 있을 수 있고, 여기서 지우고 나면 되살릴 값이 없다. */
        writeDraftMeta()
        wipe()
    }

    /// 이번 촬영을 버린다 — 메모리와 파일 모두. 저장 완료와 "폐기하고 새로 시작"이 부른다.
    func discardDraft() {
        wipe()
        drafts.clear()
        draft = nil
    }

    private func wipe() {
        cuts = []
        retakeIndex = nil
        cutsRevision += 1
        // 컷 수가 바뀌면 이전 템플릿이 그 컷 수를 지원하지 않을 수 있다(스트립 계열은 4컷 전용).
        templateID = Templates.forCount(count).first?.id ?? Templates.all[0].id
        filterID = .original
        caption = ""
    }

    /// draft를 메모리로 되살린다. 컷 디코드가 12MP 여러 장이라 메인 액터 밖으로 보낸다.
    func resumeDraft() async -> Bool {
        guard let draft else { return false }

        let store = drafts
        let wanted = draft.cutCount
        let loaded = await Task.detached(priority: .userInitiated) {
            store.loadCuts(wanted)
        }.value
        guard !loaded.isEmpty else {
            discardDraft()
            return false
        }

        count = draft.count
        mode = draft.mode
        templateID = draft.templateID
        filterID = draft.filterID
        caption = draft.caption
        cuts = loaded
        retakeIndex = nil
        cutsRevision += 1
        return true
    }

    /* 컷을 촬영 즉시 파일로 내린다. 12MP JPEG 인코딩은 100ms대라 셔터를 막지 않게 떼어 보낸다.
     * 실패는 삼킨다 — 촬영 중에 사용자가 할 수 있는 일이 없고, 원인이 저장 공간이라면 저장
     * 단계에서 같은 이유로 실패하며 그때는 문구가 뜬다. 부분 쓰기는 `DraftStore.load()`가
     * 파일 수를 세어 걸러낸다. */
    private func persist(_ image: UIImage, at index: Int) {
        let store = drafts
        Task.detached(priority: .utility) {
            try? store.writeCut(image, at: index)
        }
        writeDraftMeta()
    }

    private func writeDraftMeta() {
        guard !cuts.isEmpty else { return }
        // 24h 시계는 첫 컷에서 시작한다 — 그 전에는 지킬 것이 없다.
        let snapshot = DraftStore.Draft(
            createdAt: draft?.createdAt ?? Date(),
            count: count,
            mode: mode,
            cutCount: cuts.count,
            templateID: templateID,
            filterID: filterID,
            caption: caption
        )
        draft = snapshot
        try? drafts.save(snapshot)
    }

    func draftThumbnail(maxPixel: CGFloat) async -> UIImage? {
        let store = drafts
        return await Task.detached(priority: .userInitiated) {
            store.thumbnail(maxPixel: maxPixel)
        }.value
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
            /* 포스트가 됐으니 draft는 더 이상 미완료가 아니다(§6.4 "업로드 완료 시 draft 해제").
             * 여기서 지우지 않으면 다음 촬영이 이미 저장된 촬영에 막힌다. */
            discardDraft()
            return true
        } catch {
            // 실패했는데 피드로 넘어가면 사용자는 저장됐다고 믿는다.
            saveFailure = error
            return false
        }
    }
}
