/* JPEG 쓰기와 다운샘플 디코드.
 *
 * 합성 결과가 서버로 가면서 남은 소비처는 **진행 중인 촬영의 컷**(`DraftStore`) 하나다.
 * 인덱스·삭제·파일 URL을 다루던 메서드들은 그 소비처(`FeedStore`)와 함께 사라졌다.
 *
 * 디코드는 표시 크기에 맞춰 다운샘플하고 메인 액터에서 하지 않는다 — 12MP 컷을 뷰 본문에서
 * 통째로 디코드하면 그게 메인 스레드에서 일어난다. */

import ImageIO
import UIKit

struct PostFileStore: Sendable {
    private let vault: FileVault

    init(vault: FileVault) {
        self.vault = vault
    }

    static let fileExtension = "jpg"

    func write(_ image: UIImage, to name: String) throws {
        guard let data = image.jpegData(compressionQuality: 0.92) else {
            throw PostStoreError.encodeFailed
        }
        try vault.write(data, to: name)
    }

    /// `maxPixel`은 긴 변 기준 상한. 호출자가 표시 크기를 알고 넘긴다.
    /// nonisolated + Sendable이라 호출부에서 메인 액터 밖으로 옮겨 실행할 수 있다.
    func decode(_ name: String, maxPixel: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(vault.url(name) as CFURL, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            // EXIF 방향을 픽셀에 적용해 둔다 — 뷰가 회전 보정을 신경 쓰지 않게.
            kCGImageSourceCreateThumbnailWithTransform: true,
            // 지금 디코드해 둔다. 미루면 첫 렌더 프레임에서 디코드가 터져 스크롤이 끊긴다.
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            source, 0, options as CFDictionary
        ) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

enum PostStoreError: Error {
    case encodeFailed
}
