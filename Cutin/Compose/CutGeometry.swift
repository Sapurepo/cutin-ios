/* 컷 배치 계산 — 0.1.0의 `CutLayoutEngine`(컷 수 × 레이아웃 열거형)을 대체한다.
 *
 * 배치는 이제 서버가 준다(`Template.slots`, 그리드 영역 기준 0~1 비율). 이 파일이 하는 일은
 * 그 비율을 실제 좌표로 펴고 **거터를 먹이는 것**뿐이다 — 어떤 배치가 존재하는지는 모른다.
 * 서버 컨트롤러의 "클라이언트가 컷 수를 가정하지 않는다"가 이 형태로 지켜진다.
 *
 * ## 거터를 슬롯이 아니라 여기서 먹이는 이유
 *
 * 서버 슬롯은 **거터 0 기준**이다(맞물려 canvas를 꽉 채운다). 거터는 프레임(외형)의 값이라
 * 템플릿과 곱해지면 `템플릿 × 프레임` 개수의 슬롯이 필요해진다. 슬롯은 기하만, 거터는 외형만.
 *
 * 0.1.0은 축 길이에서 거터를 먼저 빼고 비율로 나눴다. 여기서는 각 셀을 `gutter/2`씩 안으로
 * 줄인다 — 이웃 사이는 `gutter/2 + gutter/2 = gutter`가 되고, 바깥 여백은 그리드 사각형을
 * `gutter/2` 밖으로 넓혀 상쇄한다. 결과는 시각적으로 같고 슬롯 좌표를 건드리지 않는다. */

import CoreGraphics
import Foundation

enum CutGeometry {
    /* `"3:4"` → 그리드 높이 ÷ 너비. `W:H`에서 `H/W`다.
     *
     * 파싱 실패는 정사각(1)으로 떨어진다. 서버가 새 형식을 쓰기 시작하면 비율만 어긋나고
     * 화면은 계속 뜬다 — 여기서 던지면 템플릿 하나 때문에 편집 화면 전체가 죽는다. */
    static func heightPerWidth(_ aspectRatio: String) -> CGFloat {
        let parts = aspectRatio.split(separator: ":")
        guard parts.count == 2,
              let width = Double(parts[0]), let height = Double(parts[1]),
              width > 0, height > 0
        else { return 1 }
        return CGFloat(height / width)
    }

    /// 슬롯을 그리드 사각형 안 좌표로 펴고 거터를 먹인다. 반환 순서는 컷 인덱스 순서와 같다.
    static func cells(_ slots: [TemplateSlot], in rect: CGRect, gutter: CGFloat) -> [CGRect] {
        let inset = gutter / 2
        // 바깥 여백은 프레임의 padding이 담당한다 — 그리드를 넓혀 셀 축소분을 상쇄한다.
        let outer = rect.insetBy(dx: -inset, dy: -inset)

        return slots.map { slot in
            CGRect(
                x: outer.minX + CGFloat(slot.x) * outer.width,
                y: outer.minY + CGFloat(slot.y) * outer.height,
                width: CGFloat(slot.width) * outer.width,
                height: CGFloat(slot.height) * outer.height
            ).insetBy(dx: inset, dy: inset)
        }
        // 거터가 셀보다 크면 음수 크기가 나온다. 그릴 수 없는 값이라 걸러 낸다.
        .map { $0.width > 0 && $0.height > 0 ? $0 : .zero }
    }

    /* 그릴 수 있는 템플릿인지. **서버 데이터라 `assert`로 막지 않는다** —
     * 0.1.0에서는 배치가 로컬 상수여서 불변식 위반이 곧 코드 결함이었고 크래시가 옳았다.
     * 지금은 시드가 잘못되면 앱이 죽으므로, 못 그리는 템플릿은 목록에서 빼는 것이 맞다.
     *
     * 검사 항목: 컷 수와 슬롯 수 일치 · 0~1 안에 있음 · 면적 있음 · 서로 겹치지 않음. */
    static func isRenderable(_ template: Template) -> Bool {
        guard template.cutCount > 0, template.slots.count == template.cutCount else { return false }

        let epsilon = 0.0001
        let unit = CGRect(x: -epsilon, y: -epsilon, width: 1 + epsilon * 2, height: 1 + epsilon * 2)
        let rects = template.slots.map {
            CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height)
        }

        for (index, rect) in rects.enumerated() {
            guard rect.width > epsilon, rect.height > epsilon, unit.contains(rect) else { return false }
            for other in rects[(index + 1)...] {
                let overlap = rect.intersection(other)
                guard overlap.isNull || overlap.width < epsilon || overlap.height < epsilon
                else { return false }
            }
        }
        return true
    }
}
