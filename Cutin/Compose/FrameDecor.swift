/* 프레임 장식 — 서버가 URL로 주는 상단·하단 스트립과 배경 패턴 타일.
 *
 * 프레임 계약은 원래 색과 길이뿐이었다(배경·전경·여백·거터·라운딩·푸터). 그 값만으로는
 * 하트도 곰돌이도 그릴 수 없어 "귀여운 프레임"의 상한이 색 바꾸기에서 멈춘다. 장식을 **그림**으로
 * 받으면 디자이너가 프레임을 늘려도 앱을 다시 배포하지 않는다 — 서버 시드만 바뀐다.
 *
 * ## 왜 합성기가 직접 받지 않는가
 *
 * `CutCompositor.render`는 동기 함수다(Core Graphics 캔버스에 그대로 굽는다). 다운로드를 그 안에
 * 품으려면 합성 전체가 async가 되고, `Task.detached`로 메인 액터 밖에 내보내는 지금 구조가
 * 깨진다. 그래서 호출부가 미리 받아 둔 `FrameDecor`를 요청에 실어 넘긴다.
 *
 * 실패는 조용하다. 장식은 있으면 좋은 것이고, 못 받았다고 합성을 멈추면 **네트워크가 나쁠 때
 * 사진을 저장할 수 없게 된다.** 그림이 없으면 색만 있는 프레임이 그대로 나온다. */

import UIKit

struct FrameDecor: Sendable {
    /// 그리드 위 밴드. 밴드 높이는 이 그림의 비율이 정한다(`CutCompositor`).
    var top: UIImage?
    /// 그리드 아래·푸터 위 밴드.
    var bottom: UIImage?
    var pattern: UIImage?
    /// 타일 폭 ÷ 캔버스 폭.
    var patternScale: CGFloat = Self.defaultPatternScale

    static let none = FrameDecor()

    /// 서버가 `patternScale`을 빼고 패턴만 준 경우의 값 — 폭에 타일 여섯 개.
    static let defaultPatternScale: CGFloat = 1.0 / 6

    var isEmpty: Bool { top == nil && bottom == nil && pattern == nil }
}

enum FrameDecorLoader {
    static func decor(for frame: Frame?) async -> FrameDecor {
        guard let frame else { return .none }

        async let top = image(frame.decorTopUrl)
        async let bottom = image(frame.decorBottomUrl)
        async let pattern = image(frame.patternUrl)

        return await FrameDecor(
            top: top,
            bottom: bottom,
            pattern: pattern,
            patternScale: frame.patternScale.map { CGFloat($0) } ?? FrameDecor.defaultPatternScale
        )
    }

    /* 디코드한 그림을 들고 있는다. 편집 1단계는 칩을 누를 때마다 미리보기를 다시 굽고, 저장에서
     * 한 번 더 굽는다 — URLSession 공유 캐시가 바이트는 재사용해도 PNG 디코드는 매번 다시 한다. */
    private static let cache = DecorCache()

    private static func image(_ raw: String?) async -> UIImage? {
        // 서버가 절대 URL을 주지만, 스토리지 벤더가 바뀌면 상대 경로가 올 수 있다(§`UploadTarget`).
        guard let raw, let url = URL(string: raw, relativeTo: APIConfig.baseURL) else { return nil }

        if let cached = await cache.image(for: url) { return cached }

        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = UIImage(data: data)
        else { return nil }

        await cache.store(image, for: url)
        return image
    }
}

private actor DecorCache {
    private var images: [URL: UIImage] = [:]

    func image(for url: URL) -> UIImage? { images[url] }
    func store(_ image: UIImage, for url: URL) { images[url] = image }
}
