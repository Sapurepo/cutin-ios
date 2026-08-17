/* 아바타 고르기 — 온보딩(§3.4)과 프로필(§8.1) 두 곳이 쓴다.
 *
 * `PhotosPicker`는 **사진 권한 키가 필요 없다.** 별도 프로세스에서 고르고 고른 것만 넘겨주므로
 * `NSPhotoLibraryUsageDescription` 없이 동작한다(0.1.0에서 아바타를 미룬 이유가 "읽기 권한 키가
 * 추가로 필요하다"였는데, 그 전제가 틀렸다).
 *
 * 올리는 일은 `AuthSession`이 한다 — 왕복이 넷(업로드 셋 + 프로필 PATCH)이라, 화면이 사라지면
 * 남은 왕복이 죽은 상태에 쓰인다. 이 뷰는 고르고 줄이는 데까지만 한다. */

import PhotosUI
import SwiftUI

struct AvatarPicker: View {
    let url: String?
    let nickname: String?
    var size: CGFloat = 84
    /// 사진 지우기를 허용할지. 온보딩에는 아직 지울 사진이 없다.
    var allowsRemoval = false

    @Environment(AuthSession.self) private var session
    @Environment(\.palette) private var palette

    @State private var selection: PhotosPickerItem?
    @State private var isPreparing = false

    /// 아바타 표시 크기(@3x)에 여유를 둔 값. 원본 12MP를 그대로 올릴 이유가 없다.
    private static let maxPixel: CGFloat = 512

    private var isBusy: Bool { isPreparing || session.isAuthenticating }

    var body: some View {
        /* label에 넘길 값을 **클로저 밖에서** 꺼낸다.
         *
         * `PhotosPicker`의 SDK 시그니처가 `@Sendable () -> Label`이라, 그 안에서 뷰의
         * 프로퍼티(`isBusy`·`palette`)를 읽으면 메인 액터 격리 위반이다 — SwiftUI View는
         * `body`가 `@MainActor`라 타입 전체가 그렇게 추론된다. 클로저를 프로퍼티로 빼도
         * 같다(이전 판이 그렇게 하고도 경고가 남아 있었다). 값으로 꺼내 두면 클로저는
         * 메인 액터 상태를 건드리지 않는다. */
        let isBusy = isBusy
        let palette = palette

        /* 지우기는 **길게 눌러** 나온다. 0.3.0은 아바타 밑에 "사진 지우기"가 상시 노출돼 프로필의
         * 머리가 지우기 안내로 시작했다(0.4.0 감사). 지우기는 드문 일이라 숨겨도 되고, 사진 위
         * 길게 누르기는 iOS가 가르쳐 둔 문법이다. 컨텍스트 메뉴는 PhotosPicker가 아니라 그것을
         * 감싼 컨테이너에 건다 — 픽커는 탭을 자기가 잡아 시트를 띄우는 컨트롤이라 길게 누르기가
         * 픽커에 먹혀 메뉴가 안 뜰 수 있다(리뷰). VoiceOver에는 메뉴 항목이 액션으로 노출된다. */
        ZStack {
            PhotosPicker(selection: $selection, matching: .images) {
                PickerLabel(url: url, nickname: nickname, size: size,
                            isBusy: isBusy, palette: palette)
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
        }
        .contextMenu {
            if allowsRemoval, url != nil, !isBusy {
                Button("사진 지우기", role: .destructive) { Task { await session.removeAvatar() } }
            }
        }
        .onChange(of: selection) { _, item in
            guard let item else { return }
            Task { await upload(item) }
        }
    }

    private func upload(_ item: PhotosPickerItem) async {
        isPreparing = true
        /* 고른 항목을 비우는 것을 **먼저** 예약한다. 같은 사진을 다시 고르면 `selection`이
         * 바뀌지 않아 `onChange`가 안 불린다 — 실패한 뒤 같은 사진으로 재시도하는 경로가 그렇다. */
        defer {
            selection = nil
            isPreparing = false
        }

        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage.downsampled(from: data, maxPixel: Self.maxPixel)
        else {
            // 사진 앱이 바이트를 못 준 경우(iCloud 다운로드 실패 등). 세션이 문구를 갖는다.
            session.failAvatarPreparation()
            return
        }
        await session.uploadAvatar(image)
    }
}

/* 아바타 + 카메라 배지. `AvatarPicker`의 프로퍼티로 두지 않고 타입으로 뺀 이유는 위
 * `PhotosPicker` 호출부 주석에 있다 — 필요한 값을 전부 받아 두면 메인 액터 밖에서 만들 수 있다. */
private struct PickerLabel: View {
    let url: String?
    let nickname: String?
    let size: CGFloat
    let isBusy: Bool
    let palette: Palette

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AvatarView(url: url, nickname: nickname, size: size)
                .opacity(isBusy ? 0.4 : 1)

            if isBusy {
                ProgressView().tint(palette.accentOn)
                    .frame(width: size, height: size)
            } else {
                // 누를 수 있다는 표시. 없으면 그냥 그려진 원이라 아무도 누르지 않는다.
                Image(systemName: "camera.fill")
                    .font(.system(size: size * 0.16, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: size * 0.3, height: size * 0.3)
                    .background(palette.surface, in: .circle)
                    .tokenBorder(Circle(), color: palette.border)
            }
        }
    }
}
