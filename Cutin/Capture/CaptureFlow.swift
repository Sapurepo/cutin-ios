/* 촬영 플로우 상태 — cutin-frontend `apps/mobile/src/stores/captureStore.ts`(zustand) 대체.
 * 컷 수·촬영 방식·촬영된 컷·재촬영 인덱스, 그리고 편집 선택을 촬영·편집 화면이 공유한다. */

import Observation
import UIKit

@MainActor
@Observable
final class CaptureFlow {
    /* 목표 컷 수는 **선택한 서버 템플릿이 정한다.** 0.1.0은 `CutCount` 열거형이었는데,
     * 서버 컨트롤러가 "클라이언트가 컷 수를 가정하지 않는다"고 못박아 두었다.
     * 템플릿이 없으면(목록 도착 전) 촬영을 시작할 수 없으므로 0이 안전한 초기값이다. */
    private(set) var template: Template?
    /// 합성 외형. 서버 목록의 첫 항목이 기본값이다(`TemplateCatalog.defaultFrame`).
    var frame: Frame?
    private(set) var mode: CaptureMode = .burst
    private(set) var cuts: [UIImage] = []
    /// nil이 아니면 "그 인덱스를 다시 찍는 중"
    var retakeIndex: Int?

    /* 편집 선택도 플로우가 갖는다. 편집이 한 화면이던 동안은 ComposeView의 `@State`로 충분했지만,
     * 템플릿·보정·마무리 세 화면으로 나뉘면 뒤로 넘길 때 그 화면의 상태가 사라져 선택이 초기화된다.
     * draft 영속(§5.3)도 이 값들을 파일로 내려야 하므로 소유자는 화면이 아니라 플로우여야 한다. */
    var filterID: FilterID = .original
    var caption = ""

    /* 컷 배열이 몇 번 바뀌었는지. 재촬영은 컷 수를 바꾸지 않고 한 장만 교체하므로,
     * 컷 수만 보는 미리보기는 카메라로 돌아가 다시 찍고 와도 옛 그림을 그대로 둔다. */
    private(set) var cutsRevision = 0

    var cutCount: Int { template?.cutCount ?? 0 }

    var isComplete: Bool { cutCount > 0 && cuts.count >= cutCount && retakeIndex == nil }
    /// 다음에 채울 컷의 1-based 번호 (표시용)
    var nextSlot: Int { min(cuts.count + 1, max(cutCount, 1)) }

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

    /* 만료를 다시 판정한다. §5.3은 "읽는 시점"이라고 못박았지만 이 객체는 앱 수명이라
     * `init`의 한 번만으로는 며칠 켜 둔 기기에서 30시간 지난 draft를 계속 이어쓰기로 내놓는다.
     * 진행 중인 촬영이 메모리에 있으면 건드리지 않는다 — 파일 상태로 덮어쓸 이유가 없다. */
    func refreshDraft() {
        guard cuts.isEmpty else { return }
        draft = drafts.load()
    }

    func configure(template: Template, frame: Frame?, mode: CaptureMode) {
        self.template = template
        self.frame = frame
        self.mode = mode
        /* 새 촬영은 이전 draft를 지우고 시작한다. 남겨 두면 컷 수가 줄었을 때(4컷 → 2컷)
         * 옛 `cut-2.jpg`가 살아남아 복구가 있지도 않은 컷을 되살린다. */
        discardDraft()
    }

    /* 편집 중 배치 변경. **컷 수가 같은 템플릿만 받는다** — 이미 찍은 컷이 있는 상태에서
     * 컷 수가 다른 템플릿으로 갈아타면 빈 슬롯이 생기거나 찍은 컷이 잘려 나간다.
     * 편집 화면은 같은 컷 수만 보여주므로 정상 경로에서는 거부가 일어나지 않는다. */
    func select(template: Template) {
        guard template.cutCount == cutCount else { return }
        self.template = template
    }

    /// 재촬영 중이면 해당 슬롯을 교체하고, 아니면 뒤에 붙인다.
    func addCut(_ image: UIImage) {
        let slot: Int
        if let index = retakeIndex, cuts.indices.contains(index) {
            cuts[index] = image
            retakeIndex = nil
            slot = index
        } else if cuts.count < cutCount {
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

    /* 컷과 편집 선택을 비운다. **템플릿·프레임은 건드리지 않는다** — 0.1.0은 여기서
     * 템플릿을 컷 수에 맞는 기본값으로 되돌렸는데, 컷 수 자체가 템플릿에서 나오는 지금
     * 그렇게 하면 방금 `configure`로 정한 선택을 지운다. 새 촬영의 템플릿은 호출부가 정한다. */
    private func wipe() {
        cuts = []
        retakeIndex = nil
        cutsRevision += 1
        filterID = .original
        caption = ""
        thumbnailCutIndex = nil
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

        template = draft.template
        frame = draft.frame
        mode = draft.mode
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
            mode: mode,
            cutCount: cuts.count,
            template: template,
            frame: frame,
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

    /* 미리보기와 저장이 **같은 입력**을 쓰도록 요청 생성을 한곳에 둔다.
     * 폭만 다르게 불러 화면용과 파일용을 굽는다.
     *
     * 템플릿이나 프레임이 없으면 nil이다 — 서버 목록이 오기 전에는 그릴 배치가 없다.
     * 로컬 기본값으로 대신 그리면 목록이 도착한 뒤 그림이 바뀐다. */
    func compositionRequest(outputWidth: CGFloat) -> CompositionRequest? {
        guard let template, let frame else { return nil }
        return CompositionRequest(
            images: cuts,
            template: template,
            frame: frame,
            filter: filterID,
            stampDate: Date(),
            outputWidth: outputWidth
        )
    }

    // MARK: - 발행

    /* 발행 진행 상태를 화면이 아니라 플로우가 갖는다.
     *
     * 마무리 화면의 `@State`로 두면 저장을 누른 뒤 뒤로 갔다 다시 들어올 때 새 화면이
     * 만들어지면서 "저장 중"이 초기화된다. 그 상태에서 다시 누르면 **한 번의 촬영이 두 번
     * 올라간다.** 실패 문구도 같은 이유로 죽은 화면에 쓰여 사라진다. */
    private(set) var saveFailure: Error?

    /// 공개 범위(§6.4). 0.1.0에는 저장할 곳이 없어 UI를 만들지 않았다.
    /// 서버 기본값과 같은 `friends`로 시작한다 — 처음 쓰는 사람에게 전체 공개는 놀라운 기본값이다.
    var visibility: PostVisibility = .friends

    /* 대표 컷(§6.3). nil이면 **미지정**이고 서버가 첫 컷을 기본으로 쓴다 — 그 구분이 화면 동작을
     * 가른다: 직접 고른 포스트만 프로필 그리드 맨 앞에 고정된다(0.3.0 제품 결정).
     * 그래서 기본값을 0으로 채우지 않는다 — 채우면 모든 포스트가 고정돼 고정이 무의미해진다.
     *
     * draft 파일에는 내리지 않는다 — `visibility`와 같은 결정이다(마무리 단계의 선택은
     * 발행 직전 값이라 이어쓰기에서 다시 고르는 편이 안전하다). */
    var thumbnailCutIndex: Int?

    enum CommitFailure: LocalizedError {
        /// 서버 템플릿 목록이 없어 그릴 배치가 없다.
        case templateMissing

        var errorDescription: String? {
            "템플릿을 불러오지 못해 저장할 수 없어요. 잠시 후 다시 시도해주세요"
        }
    }

    /* 합성해서 서버에 발행한다. 성공하면 발행된 포스트.
     *
     * 0.1.0은 여기서 파일 하나를 쓰고 끝났다. 지금은 왕복이 컷 수에 따라 열여섯 번쯤 되고
     * (`PostPublisher`), 그 순서와 진행 표시는 전부 발행기가 갖는다. 이 메서드가 하는 일은
     * **굽기 전에 메타데이터를 붙잡는 것**뿐이다 — 렌더는 200ms대가 걸리고 그 사이 사용자가
     * 뒤로 가 보정을 바꾸면, 올라간 그림과 올라간 캡션이 서로 다른 순간의 것이 된다. */
    func commit(with publisher: PostPublisher, to store: PostStore) async -> Bool {
        guard !publisher.isPublishing else { return false }
        saveFailure = nil

        guard let request = compositionRequest(outputWidth: CutCompositor.saveWidth),
              let template, let frame
        else {
            saveFailure = CommitFailure.templateMissing
            return false
        }
        let bakedCuts = cuts
        let bakedCaption = caption
        let bakedVisibility = visibility
        let bakedThumbnail = thumbnailCutIndex

        let baked = await Task.detached(priority: .userInitiated) {
            CutCompositor.render(request)
        }.value

        do {
            let post = try await publisher.publish(PostPublisher.Request(
                template: template,
                frame: frame,
                cuts: bakedCuts,
                composed: baked,
                caption: bakedCaption,
                visibility: bakedVisibility,
                thumbnailCutIndex: bakedThumbnail
            ))
            store.insertPublished(post)
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
