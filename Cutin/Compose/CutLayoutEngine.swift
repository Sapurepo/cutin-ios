/* 컷 배치 규칙 — cutin-frontend `apps/mobile/src/components/cutFrame.tsx`의 flex 트리를
 * 좌표 계산으로 옮겼다. 합성(CutCompositor)과 화면 프리뷰가 같은 함수를 쓰도록 순수 함수로 둔다.
 *
 * 원본 명명 주의: RN의 `flexDirection: "row"`는 가로 배치다.
 * 따라서 `.row`(booth-strip)는 원본에서 `colWrap`을 쓰므로 **세로 스택**,
 * `.strip`(wide-strip)은 `rowWrap`이므로 **가로 배치**다. 혼동하기 쉬워 그대로 보존했다. */

import CoreGraphics

enum CutLayoutEngine {
    private enum Axis { case horizontal, vertical }

    /// 컷 수와 레이아웃에 맞는 셀 사각형들을 정사각 `rect` 안에서 계산한다.
    /// 반환 순서는 컷 인덱스 순서와 같다.
    static func cells(count: CutCount, layout: CutLayout, in rect: CGRect, gutter: CGFloat) -> [CGRect] {
        let cells = rects(count: count, layout: layout, in: rect, gutter: gutter)
        assert(holdsInvariants(cells, count: count, in: rect), "레이아웃 불변식 위반: \(count.rawValue)컷 \(layout)")
        return cells
    }

    /* 테스트 타깃이 없는 동안 레이아웃의 유일한 실행 검증.
     *
     * 특히 아래 2xN 기본 분기의 `count.rawValue / columns`는 정수 나눗셈이라, 홀수 컷 수가
     * 추가되면(3컷·5컷) 조용히 셀을 하나 덜 만들고 마지막 컷이 사라진다. 셀 수 불일치는
     * 그 자리에서 잡힌다. `assert`는 릴리즈에서 조건식째로 평가되지 않는다. */
    private static func holdsInvariants(_ cells: [CGRect], count: CutCount, in rect: CGRect) -> Bool {
        guard cells.count == count.rawValue else { return false }

        // 좌표 누적 오차 허용치. 셀 변 길이는 최소 수십 pt이므로 이 값으로 겹침을 놓치지 않는다.
        let epsilon: CGFloat = 0.01
        let bounds = rect.insetBy(dx: -epsilon, dy: -epsilon)

        for (index, cell) in cells.enumerated() {
            guard cell.width > 0, cell.height > 0, bounds.contains(cell) else { return false }
            for other in cells[(index + 1)...] {
                let overlap = cell.intersection(other)
                guard overlap.isNull || overlap.width < epsilon || overlap.height < epsilon else { return false }
            }
        }
        return true
    }

    private static func rects(count: CutCount, layout: CutLayout, in rect: CGRect, gutter: CGFloat) -> [CGRect] {
        switch (count, layout) {
        case (.one, _):
            return [rect]

        case (.two, _):
            return split(rect, axis: .horizontal, weights: [1, 1], gutter: gutter)

        // 포토부스 스트립 — 세로로 4장
        case (.four, .row):
            return split(rect, axis: .vertical, weights: [1, 1, 1, 1], gutter: gutter)

        // 와이드 스트립 — 가로로 4장
        case (.four, .strip):
            return split(rect, axis: .horizontal, weights: [1, 1, 1, 1], gutter: gutter)

        // 왼쪽 큰 컷 1장 + 오른쪽 세로 3장
        case (.four, .bigLeft):
            let columns = split(rect, axis: .horizontal, weights: [1.6, 1], gutter: gutter)
            let right = split(columns[1], axis: .vertical, weights: [1, 1, 1], gutter: gutter)
            return [columns[0]] + right

        // 2xN 그리드 (4컷 기본 2x2, 6컷 2x3)
        default:
            let columns = 2
            let rows = count.rawValue / columns
            let rowRects = split(rect, axis: .vertical, weights: Array(repeating: 1, count: rows), gutter: gutter)
            return rowRects.flatMap {
                split($0, axis: .horizontal, weights: [1, 1], gutter: gutter)
            }
        }
    }

    /// flex 비율(`weights`)대로 축을 따라 나누고 사이에 `gutter`를 둔다.
    private static func split(_ rect: CGRect, axis: Axis, weights: [CGFloat], gutter: CGFloat) -> [CGRect] {
        guard weights.count > 1 else { return [rect] }

        let total = weights.reduce(0, +)
        let available = (axis == .horizontal ? rect.width : rect.height)
            - gutter * CGFloat(weights.count - 1)

        var result: [CGRect] = []
        var offset = axis == .horizontal ? rect.minX : rect.minY

        for weight in weights {
            let length = available * (weight / total)
            switch axis {
            case .horizontal:
                result.append(CGRect(x: offset, y: rect.minY, width: length, height: rect.height))
            case .vertical:
                result.append(CGRect(x: rect.minX, y: offset, width: rect.width, height: length))
            }
            offset += length + gutter
        }
        return result
    }
}
