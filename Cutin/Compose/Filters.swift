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
    /// CIContext는 SDK에서 이미 Sendable이라 이 전역 상수는 Swift 6에서 그대로 통과한다.
    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    /// 셀에 그려질 크기로 먼저 줄인 뒤 필터를 적용한다.
    ///
    /// 12MP 원본에 매트릭스를 걸면 화면에 남지도 않는 화소까지 계산한다 — 540px 프리뷰의
    /// 4컷 셀 하나는 30만 화소가 안 된다. 컬러 매트릭스는 화소별 선형 변환(`f(x) = Mx + b`)이라
    /// 가중평균인 축소와 순서를 바꿔도 결과가 같다(`avg(Mx+b) == M·avg(x)+b`).
    ///
    /// 어긋나는 곳은 0·1로 **포화되어 클램프되는 화소**뿐이다. 축소를 먼저 하면 클램프에
    /// 잘려 나가던 여분이 평균에 남기 때문이다. 그래서 차이는 행 합이 1을 넘는 필터에서만
    /// 유의미하다 — `sepia`는 R행 합이 1.35로 가장 크고, `mono`는 Rec.709 luma라 정확히 1.0이다.
    ///
    /// 1080px 저장 출력 기준 실측(4032x3024 입력 4장, 채널 최대 / 평균):
    /// `original` 0 / 0 (매트릭스가 없어 축소 자체를 건너뛰므로 바이트 동일),
    /// `mono`·`warm`·`cool`·`soft`·`film` ≤ 5 / ≤ 0.34, `sepia` 23 / 0.39.
    /// 최대치는 2px 주기 밝은 격자를 넣은 적대적 입력에서 나온 값이고, 매끄러운 밝은 입력에서는
    /// `sepia`도 7 / 0.01이다.
    static func apply(_ filterID: FilterID, to image: UIImage, downsampledTo size: CGSize) -> UIImage {
        guard filterID.matrix != nil else { return image }
        return apply(filterID, to: downsampled(image, to: size))
    }

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

    /// 원본이 이미 목표보다 작으면 그대로 둔다 — 늘려 담아도 없던 화소가 생기지 않는다.
    /// 축소는 합성기가 쓰는 것과 같은 Core Graphics 리샘플이라, 바뀌는 것은 "언제 줄이는가"뿐이다.
    private static func downsampled(_ image: UIImage, to size: CGSize) -> UIImage {
        guard size.width >= 1, size.height >= 1,
              size.width < image.size.width, size.height < image.size.height
        else { return image }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        /* `.automatic`은 기기에 따라 확장 범위(넓은 색역)로 해석된다. 이 중간 비트맵이 곧
         * 매트릭스의 입력이므로, 범위를 고정하지 않으면 위의 "sRGB 값에 직접 적용한다"는
         * 결정이 기기별로 달라진다. mono의 Rec.709 계수와 film의 -0.075 오프셋은
         * 표준 범위 sRGB를 전제로 이식된 값이다. */
        format.preferredRange = .standard

        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
