/* QR 코드 — 네컷과 촬영 영상을 폰 없이 남에게 보여주는 수단.
 *
 * 인생네컷 부스가 인화지에 QR을 찍어 주는 것과 같은 자리다. 링크를 카카오톡으로 보내는 것과
 * 다른 점은 **그 자리에서 상대 카메라로 바로 찍는다**는 것이다 — 아이디도 앱도 필요 없다.
 * 그래서 이 화면이 유입의 첫 접점이 된다.
 *
 * ## 링크는 공유 링크와 같다
 *
 * `GET /posts/{id}/share`가 주는 주소를 그대로 QR로 만든다. 별도의 QR 전용 링크를 만들면
 * 같은 페이지로 가는 주소가 둘이 되고, 만료·권한 규칙을 두 곳에서 관리하게 된다.
 *
 * 생성은 Core Image의 `CIQRCodeGenerator`다 — 의존성이 늘지 않고, 만드는 데 왕복이 없다. */

import CoreImage.CIFilterBuiltins
import SwiftUI

struct PostQRSheet: View {
    let post: Post
    /// 닫힐 때 알린다. 발행 직후에는 이 시점에 촬영 화면을 접는다.
    var onClose: (() -> Void)?

    @Environment(PostStore.self) private var store
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var url: URL?
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.x5) {
                Spacer(minLength: 0)

                code

                VStack(spacing: Spacing.x2) {
                    Text(headline)
                        .font(Typography.body)
                        .multilineTextAlignment(.center)
                    Text("휴대폰 카메라로 비추기만 하면 열려요")
                        .font(Typography.caption)
                        .foregroundStyle(palette.textSecondary)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .padding(Spacing.x5)
            .background(palette.bg)
            .navigationTitle("QR 코드")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
        }
        .task { await prepare() }
        .onDisappear { onClose?() }
    }

    /* 영상이 있는지에 따라 문구가 달라진다. "촬영 영상을 볼 수 있어요"라고 해 놓고 정지 이미지만
     * 나오면, 스캔한 사람이 아니라 보여준 사람이 민망해진다. */
    private var headline: String {
        post.motion == nil
            ? "스캔하면 이 네컷을 볼 수 있어요"
            : "스캔하면 네컷과 촬영 영상을 볼 수 있어요"
    }

    @ViewBuilder
    private var code: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.lg)
                /* QR은 **흰 바탕 위 검은 모듈**이어야 인식률이 안정적이다. 다크 모드에서 반전시키면
                 * 못 읽는 카메라 앱이 있어, 이 카드만 테마를 따르지 않는다. */
                .fill(.white)
                .frame(width: 280, height: 280)

            if let image = qrImage {
                Image(uiImage: image)
                    .interpolation(.none)   // 모듈 경계가 흐려지면 인식률이 떨어진다
                    .resizable()
                    .frame(width: 232, height: 232)
            } else if let failure {
                Text(failure)
                    .font(Typography.caption)
                    .foregroundStyle(.black.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(Spacing.x5)
            } else {
                ProgressView().tint(.black.opacity(0.4))
            }
        }
    }

    private var qrImage: UIImage? {
        url.flatMap(QRCode.image(for:))
    }

    private func prepare() async {
        guard url == nil else { return }
        do {
            url = try await store.shareLink(id: post.id)
        } catch let error as APIError {
            // 비공개 포스트는 서버가 막는다(`POST_NOT_SHAREABLE`) — 서버 문구가 이유를 말해 준다.
            failure = error.serverMessage ?? "QR 코드를 만들지 못했어요"
        } catch {
            failure = "QR 코드를 만들지 못했어요"
        }
    }
}

/// `sheet(item:)`이 `Identifiable`을 요구한다. 서버가 준 id를 그대로 신원으로 쓴다.
extension Post: Identifiable {}

enum QRCode {
    /* 문자열을 QR 이미지로. 오류 정정 수준은 `M`(기본)이다 — 화면으로 보여 주는 QR이라
     * 인화물처럼 긁히거나 접힐 일이 없고, 수준을 올리면 모듈이 촘촘해져 작은 화면에서 더 불리하다. */
    static func image(for url: URL) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        guard let output = filter.outputImage else { return nil }

        /* 생성된 이미지는 모듈당 1픽셀이라 그대로 키우면 흐려진다. 정수 배로 먼저 키워
         * 픽셀 경계를 살린다. */
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
