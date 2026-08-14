/* 이미지 업로드 — 왕복 셋을 하나로 묶는다.
 *
 *   ① `POST /media/uploads`      목적지 발급 (미디어가 pending으로 생긴다)
 *   ② `PUT  {url}`               바이트 전송
 *   ③ `POST /media/{id}/complete` 크기를 알려 ready로 만든다
 *
 * 셋을 호출부마다 늘어놓지 않는 이유: **순서를 틀리면 조용히 아프다.** ③을 빠뜨린 미디어는
 * pending으로 남고, 서버는 pending 미디어를 포스트에 붙이지 못하게 막는다(`findReadyByIds`).
 * 화면에서는 "업로드는 됐는데 발행만 안 된다"로 보인다.
 *
 * `actor`가 아니라 `struct`인 이유: 상태가 없다. 전송 계층이 이미 액터고, 동시성 제어는
 * 거기 있다. 여기서는 세 왕복의 순서만 지킨다.
 *
 * ## 크기를 이미지에서 읽는 이유
 *
 * ③이 요구하는 `width`·`height`는 **실제로 올린 바이트의 크기**여야 한다. 호출부가 따로
 * 넘기게 두면 리사이즈를 넣었을 때 값과 바이트가 갈린다 — 서버는 그 값을 그대로 믿는다. */

import UIKit

struct MediaUploader: Sendable {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    /// JPEG 압축률. 컷 원본은 이미 12MP라 화질보다 전송 시간이 먼저 아프다.
    private static let quality: CGFloat = 0.9

    /* 이미지 한 장을 올리고 준비된 미디어를 돌려준다.
     *
     * 실패는 그대로 던진다. 어느 단계에서 끊겼는지에 따라 사용자가 할 수 있는 일이 다르지 않고
     * (다시 시도하는 것뿐), 서버에 남은 pending 미디어는 서버가 정리한다(`purge`). */
    func upload(_ image: UIImage, kind: MediaKind) async throws -> Media {
        guard let data = image.jpegData(compressionQuality: Self.quality) else {
            throw UploadFailure.encodingFailed
        }

        let target = try await client.send(
            .post, "/media/uploads",
            body: CreateUploadBody(kind: ServerEnum(kind), mime: ServerEnum(.jpeg)),
            as: UploadTarget.self
        )
        try await client.upload(data, to: target)

        /* 픽셀 크기를 쓴다. `UIImage.size`는 포인트 단위라 `scale`이 1이 아니면 실제 바이트의
         * 픽셀 수와 다르다 — 합성 결과는 scale 1로 굽지만(`CutCompositor`), 사진 앱에서 온
         * 아바타는 그렇지 않다. */
        let pixels = image.pixelSize
        return try await client.send(
            .post, "/media/\(target.mediaId.path)/complete",
            body: CompleteUploadBody(width: pixels.width, height: pixels.height),
            as: Media.self
        )
    }

    enum UploadFailure: LocalizedError {
        /// JPEG 인코딩 실패 — CIImage만 있고 CGImage가 없는 UIImage 등.
        case encodingFailed

        var errorDescription: String? {
            "이미지를 준비하지 못했어요. 다시 시도해주세요"
        }
    }
}

extension UIImage {
    /// 실제 픽셀 크기. `size`는 포인트라 `scale`을 곱해야 바이트와 맞는다.
    var pixelSize: (width: Int, height: Int) {
        if let cgImage {
            return (cgImage.width, cgImage.height)
        }
        return (Int(size.width * scale), Int(size.height * scale))
    }

    /* 사진 앱에서 온 바이트를 **줄여서** 디코드한다. `UIImage(data:)`는 12MP를 그대로 들고,
     * 아바타 한 장이 수 MB가 되어 전송 시간과 서버 저장 공간을 함께 먹는다
     * (서버 상한은 15MB라 막히지는 않지만, 84pt 원형에 12MP를 올릴 이유가 없다).
     *
     * `PostFileStore.decode`와 같은 ImageIO 경로다. 그쪽은 파일 URL, 여기는 메모리 바이트라
     * 소스를 만드는 줄만 다르다. */
    static func downsampled(from data: Data, maxPixel: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            // EXIF 방향을 픽셀에 적용해 둔다 — 세로로 찍은 사진이 눕지 않게.
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            source, 0, options as CFDictionary
        ) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
