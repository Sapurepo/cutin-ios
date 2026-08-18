/* 효과음 — `Haptics`와 짝이다. 넷뿐이다.
 *   tap      부품을 눌렀다 — 설정 톱니, 피드의 알림 종, 촬영 설정의 배치 고르기
 *   tick     카운트다운 3·2·1
 *   pop      반응을 남길 때 (Haptics.light와 함께)
 *   success  발행 완료 (Haptics.success와 함께)
 *
 * **셔터에는 얹지 않는다.** `AVCapturePhotoOutput`이 시스템 셔터음을 이미 내고, 한국·일본 기기는
 * 무음이어도 난다 — 그 위에 하나 더 얹으면 두 번 울린다. 인트로에도 넣지 않는다.
 *
 * ## `AVAudioPlayer` + `.ambient`인 이유
 *
 * 처음(#53)엔 시스템 사운드 API(`AudioServicesPlaySystemSound`)였다 — 세션이 필요 없고 지연이 없어서.
 * 그런데 실기기에서 무음이 아닌데도 들리지 않았다(사용자). 그 API는 벨소리 볼륨을 따르고 앱 오디오
 * 세션 밖에서 돌아 왜 조용한지 볼 길이 없다. `AVAudioPlayer`는 **미디어 볼륨**을 따르니 옆면
 * 버튼으로 바로 조절되고, 카테고리를 우리가 정하므로 조건이 분명하다.
 *   `.ambient` = 무음 스위치를 따르고, 듣던 음악을 끊지 않는다(기본 `.soloAmbient`는 끊는다).
 * 카메라 세션은 오디오 입력이 없어 이 카테고리를 건드리지 않지만, 재생 직전마다 확인해 되돌린다.
 *
 * 파일은 `Scripts/sounds/make.py`가 만든 번들의 `.caf`. 플레이어는 처음 부를 때 만들어 앱이 사는
 * 동안 들고 있는다(`prepareToPlay`) — 지역변수로 만들면 소리 나기 전에 해제된다.
 * 끄는 자리는 프로필의 설정 메뉴("효과음"). 기본은 켬 — 무음 스위치가 이미 있으니 두 번 묻지 않는다. */

import AVFoundation
import SwiftUI

@MainActor
enum SoundEffects {
    /// 설정 토글의 키(`@AppStorage`). 값이 없으면 켬.
    static let enabledKey = "sound.enabled"

    static func tap() { play(.tap) }
    static func tick() { play(.tick) }
    static func pop() { play(.pop) }
    static func success() { play(.success) }

    // MARK: -

    private enum Sound: String { case tap, tick, pop, success }

    private static var players: [Sound: AVAudioPlayer] = [:]

    private static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    private static func play(_ sound: Sound) {
        guard isEnabled, let player = player(for: sound) else { return }
        let session = AVAudioSession.sharedInstance()
        if session.category != .ambient {
            try? session.setCategory(.ambient)
        }
        // 연타하면 처음부터 다시 — 반응을 두 번 눌렀는데 소리가 한 번이면 두 번째가 안 먹은 것 같다.
        player.currentTime = 0
        player.play()
    }

    private static func player(for sound: Sound) -> AVAudioPlayer? {
        if let player = players[sound] { return player }
        guard let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "caf") else {
            assertionFailure("효과음 \(sound.rawValue).caf가 번들에 없다 — Scripts/sounds/make.py")
            return nil
        }
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player.prepareToPlay()
        players[sound] = player
        return player
    }
}

/* `Menu`에 tap 소리를 붙이는 길. Menu는 열리는 콜백이 없고, 눌리는 순간(터치 다운) 메뉴가 뜨면서
 * 같이 단 제스처를 끊는다 — `simultaneousGesture(TapGesture)`는 안 울리고, `DragGesture(0)`는
 * 메뉴를 막는다(둘 다 시뮬레이터에서 확인). `.menuStyle(.button)`을 주면 버튼 스타일이 먹고,
 * 거기서 `isPressed`가 켜지는 순간을 들을 수 있다. 라벨은 그대로 돌려주므로 생김새는 안 바뀐다. */
struct TapSoundButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { SoundEffects.tap() }
            }
    }
}
