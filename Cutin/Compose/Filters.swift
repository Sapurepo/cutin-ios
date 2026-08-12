/* 보정 필터 프리셋 — cutin-frontend `apps/mobile/src/features/capture/filters.ts`에서 이식.
 * 4x5 color matrix(20원소) 값은 원본 그대로 두고 적용 방식만 CIColorMatrix로 바꿨다.
 *
 * RN판과의 결정적 차이: 원본은 filterId를 메타데이터로만 저장하고 렌더 시점에 적용했다
 * ("이미지 베이킹 없음"). 여기서는 실제로 픽셀에 구워 단일 이미지로 남긴다. */

import CoreImage
import UIKit

enum FilterID: String, CaseIterable, Codable, Identifiable, Sendable {
    case original, mono, soft, warm, cool, film, sepia

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .original: return "원본"
        case .mono: return "흑백"
        case .soft: return "소프트"
        case .warm: return "웜"
        case .cool: return "쿨"
        case .film: return "필름"
        case .sepia: return "세피아"
        }
    }

    /// 4x5 color matrix — 행 순서 R/G/B/A, 각 행은 `[r, g, b, a, offset]`.
    /// nil이면 원본 그대로.
    var matrix: [CGFloat]? {
        // Rec.709 luma 가중치 — 흑백 변환 표준 계수
        let l: (CGFloat, CGFloat, CGFloat) = (0.2126, 0.7152, 0.0722)
        switch self {
        case .original:
            return nil
        case .mono:
            return [
                l.0, l.1, l.2, 0, 0,
                l.0, l.1, l.2, 0, 0,
                l.0, l.1, l.2, 0, 0,
                0, 0, 0, 1, 0,
            ]
        case .soft:
            return [
                1.05, 0, 0, 0, 0.05,
                0, 1.05, 0, 0, 0.05,
                0, 0, 1.05, 0, 0.05,
                0, 0, 0, 1, 0,
            ]
        case .warm:
            return [
                1.06, 0, 0, 0, 0,
                0, 1, 0, 0, 0,
                0, 0, 0.93, 0, 0,
                0, 0, 0, 1, 0,
            ]
        case .cool:
            return [
                0.94, 0, 0, 0, 0,
                0, 1, 0, 0, 0,
                0, 0, 1.08, 0, 0,
                0, 0, 0, 1, 0,
            ]
        case .film:
            return [
                1.15, 0, 0, 0, -0.075,
                0, 1.15, 0, 0, -0.075,
                0, 0, 1.15, 0, -0.075,
                0, 0, 0, 1, 0,
            ]
        case .sepia:
            return [
                0.393, 0.769, 0.189, 0, 0,
                0.349, 0.686, 0.168, 0, 0,
                0.272, 0.534, 0.131, 0, 0,
                0, 0, 0, 1, 0,
            ]
        }
    }
}

enum ImageFilterer {
    /// workingColorSpace를 비워 sRGB 값에 직접 매트릭스를 적용한다.
    /// (기본 CIContext는 선형 공간에서 계산해 RN판과 결과가 달라진다)
    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    /// 필터를 실제 픽셀에 적용한다. 실패하면 원본을 그대로 돌려준다.
    static func apply(_ filterID: FilterID, to image: UIImage) -> UIImage {
        guard let m = filterID.matrix, let input = CIImage(image: image) else { return image }

        let filter = CIFilter(name: "CIColorMatrix")
        filter?.setValue(input, forKey: kCIInputImageKey)
        filter?.setValue(CIVector(x: m[0], y: m[1], z: m[2], w: m[3]), forKey: "inputRVector")
        filter?.setValue(CIVector(x: m[5], y: m[6], z: m[7], w: m[8]), forKey: "inputGVector")
        filter?.setValue(CIVector(x: m[10], y: m[11], z: m[12], w: m[13]), forKey: "inputBVector")
        filter?.setValue(CIVector(x: m[15], y: m[16], z: m[17], w: m[18]), forKey: "inputAVector")
        filter?.setValue(CIVector(x: m[4], y: m[9], z: m[14], w: m[19]), forKey: "inputBiasVector")

        guard let output = filter?.outputImage,
              let cgImage = context.createCGImage(output, from: output.extent)
        else { return image }

        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }
}
