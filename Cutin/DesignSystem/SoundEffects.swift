/* 효과음 — `Haptics`와 짝이다. 셋뿐이고, 자리도 셋뿐이다.
 *   tick     카운트다운 3·2·1
 *   pop      반응을 남길 때 (Haptics.light와 함께)
 *   success  발행 완료 (Haptics.success와 함께)
 *
 * **셔터에는 얹지 않는다.** `AVCapturePhotoOutput`이 시스템 셔터음을 이미 내고, 한국·일본 기기는
 * 무음이어도 난다 — 그 위에 하나 더 얹으면 두 번 울린다. 탭마다 소리 내는 SNS는 없다(BeReal ·
 * Instagram은 햅틱 위주) — 인트로에도 넣지 않는다.
 *
 * ## 시스템 사운드 API인 이유
 *
 * `AudioServicesPlaySystemSound`는 오디오 세션을 잡지 않아 듣던 음악이 끊기지 않고, 무음 스위치와
 * 벨소리 볼륨을 따르며, 지연이 없다. `AVAudioPlayer`는 카테고리를 골라야 하고(`.playback`이면
 * 음악을 끊고 무음을 무시한다) 인스턴스를 들고 있어야 한다 — 짧은 UI 소리에 그만한 값어치가 없다.
 * 내장 사운드 ID(1104 등)는 문서화되지 않아 쓰지 않는다 — 번들의 `.caf`를 등록한다
 * (`Scripts/sounds/make.py`가 만든다). 등록은 처음 부를 때 한 번, 앱이 사는 동안 유지한다.
 *
 * 끄는 자리는 프로필의 설정 메뉴("효과음"). 기본은 켬 — 무음 스위치가 이미 있으니 두 번 묻지 않는다. */

import AudioToolbox
import Foundation

@MainActor
enum SoundEffects {
    /// 설정 토글의 키(`@AppStorage`). 값이 없으면 켬.
    static let enabledKey = "sound.enabled"

    static func tick() { play(.tick) }
    static func pop() { play(.pop) }
    static func success() { play(.success) }

    // MARK: -

    private enum Sound: String { case tick, pop, success }

    private static var ids: [Sound: SystemSoundID] = [:]

    private static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    private static func play(_ sound: Sound) {
        guard isEnabled, let id = id(for: sound) else { return }
        AudioServicesPlaySystemSound(id)
    }

    private static func id(for sound: Sound) -> SystemSoundID? {
        if let id = ids[sound] { return id }
        guard let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "caf") else {
            assertionFailure("효과음 \(sound.rawValue).caf가 번들에 없다 — Scripts/sounds/make.py")
            return nil
        }
        var id: SystemSoundID = 0
        guard AudioServicesCreateSystemSoundID(url as CFURL, &id) == kAudioServicesNoError else { return nil }
        ids[sound] = id
        return id
    }
}
