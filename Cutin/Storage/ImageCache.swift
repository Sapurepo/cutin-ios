/* 디코드 결과 캐시. LazyVStack은 셀이 화면에 다시 들어올 때마다 `.task`를 다시 돌리므로
 * 캐시가 없으면 스크롤을 위아래로 흔드는 동안 같은 파일을 계속 다시 디코드한다.
 *
 * NSCache를 쓰는 이유는 메모리 압박 시 알아서 비우기 때문이다 — 컷 이미지는 한 장이 수 MB라
 * 상한 없는 딕셔너리로 들고 있으면 촬영 중에 메모리 경고를 맞는다. */

import UIKit

/// NSCache는 자체적으로 스레드 안전하다. 락을 더 씌우지 않는다는 뜻으로 unchecked를 쓴다.
final class ImageCache: @unchecked Sendable {
    private let cache = NSCache<NSString, UIImage>()

    /// 개수가 아니라 바이트로 제한한다 — 컷 한 장이 1080²×4 ≈ 4.6MB라 개수 상한은 실제 사용량을
    /// 통제하지 못한다.
    init(totalCostLimit: Int = 64 * 1024 * 1024) {
        cache.totalCostLimit = totalCostLimit
    }

    func image(_ name: String, maxPixel: CGFloat) -> UIImage? {
        cache.object(forKey: key(name, maxPixel))
    }

    func store(_ image: UIImage, for name: String, maxPixel: CGFloat) {
        cache.setObject(image, forKey: key(name, maxPixel), cost: image.byteCost)
    }

    func removeAll() {
        cache.removeAllObjects()
    }

    /// 같은 파일을 크기별로 따로 캐시한다 — 피드 카드와 그리드 셀이 같은 포스트를 다른 크기로 쓴다.
    private func key(_ name: String, _ maxPixel: CGFloat) -> NSString {
        "\(name)@\(Int(maxPixel))" as NSString
    }
}

private extension UIImage {
    /// 디코드된 비트맵의 대략적 크기 (RGBA 4바이트)
    var byteCost: Int {
        guard let cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }
}
