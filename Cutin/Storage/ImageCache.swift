/* 디코드 결과 캐시. LazyVStack은 셀이 화면에 다시 들어올 때마다 `.task`를 다시 돌리므로
 * 캐시가 없으면 스크롤을 위아래로 흔드는 동안 같은 파일을 계속 다시 디코드한다.
 *
 * NSCache를 쓰는 이유는 메모리 압박 시 알아서 비우기 때문이다 — 컷 이미지는 한 장이 수 MB라
 * 상한 없는 딕셔너리로 들고 있으면 촬영 중에 메모리 경고를 맞는다. */

import UIKit

/// 호출부(FeedStore)가 메인 액터라 캐시도 메인 액터에 둔다 — 락 없이도 경합이 없다.
@MainActor
final class ImageCache {
    private let cache = NSCache<NSString, UIImage>()
    /// 지금까지 요청된 크기들. NSCache는 키를 열거할 수 없어 파일 단위 삭제에 필요하다.
    private var sizes: Set<Int> = []

    /// 개수가 아니라 바이트로 제한한다 — 컷 한 장이 1080²×4 ≈ 4.6MB라 개수 상한은 실제 사용량을
    /// 통제하지 못한다.
    init(totalCostLimit: Int = 64 * 1024 * 1024) {
        cache.totalCostLimit = totalCostLimit
    }

    func image(_ name: String, maxPixel: CGFloat) -> UIImage? {
        cache.object(forKey: key(name, maxPixel))
    }

    func store(_ image: UIImage, for name: String, maxPixel: CGFloat) {
        sizes.insert(Int(maxPixel))
        cache.setObject(image, forKey: key(name, maxPixel), cost: image.byteCost)
    }

    /// 삭제된 포스트의 비트맵을 남겨 두면 다시 보여줄 수 없는 이미지가 살아 있는 항목을 밀어낸다.
    func remove(_ name: String) {
        for size in sizes {
            cache.removeObject(forKey: key(name, CGFloat(size)))
        }
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
