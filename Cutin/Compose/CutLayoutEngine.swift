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
