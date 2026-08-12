/* 촬영 플로우 상태 — cutin-frontend `apps/mobile/src/stores/captureStore.ts`(zustand) 대체.
 * 컷 수·촬영 방식·촬영된 컷·재촬영 인덱스를 들고 촬영 화면과 합성 화면이 공유한다. */

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

    var isComplete: Bool { cuts.count >= count.rawValue && retakeIndex == nil }
    /// 다음에 채울 컷의 1-based 번호 (표시용)
    var nextSlot: Int { min(cuts.count + 1, count.rawValue) }

    func configure(count: CutCount, mode: CaptureMode) {
        self.count = count
        self.mode = mode
        cuts = []
        retakeIndex = nil
    }

    /// 재촬영 중이면 해당 슬롯을 교체하고, 아니면 뒤에 붙인다.
    func addCut(_ image: UIImage) {
        if let index = retakeIndex, cuts.indices.contains(index) {
            cuts[index] = image
            retakeIndex = nil
        } else if cuts.count < count.rawValue {
            cuts.append(image)
        }
    }

    func toggleRetake(_ index: Int) {
        retakeIndex = (retakeIndex == index) ? nil : index
    }

    func reset() {
        cuts = []
        retakeIndex = nil
    }
}
