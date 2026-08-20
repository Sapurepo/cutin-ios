/* 효과음 — `Haptics`와 짝이다. iOS가 쓰는 **바로 그 소리**를 쓴다(사용자: "iOS의 사운드를 그대로").
 *   tap        부품을 눌렀다 — 설정 톱니 · 피드의 알림 종 · 촬영 설정의 배치 고르기 → 키보드 클릭
 *   tick       카운트다운 3·2, 마지막 1은 따로 → 카메라 앱 셀프타이머의 두 소리
 *   pop        반응을 남길 때 (Haptics.light와 함께) → iMessage 탭백을 보낼 때의 소리
 *   success    발행 완료 (Haptics.success와 함께) → iMessage 전송음(올라갔다)
 *   toggle     효과음 설정을 켜고 끌 때 → 켜기 Tink(높게)·끄기 Tock(낮게)
 *
 * **셔터에는 얹지 않는다.** `AVCapturePhotoOutput`이 시스템 셔터음을 이미 내고, 한국·일본 기기는
 * 무음이어도 난다. 인트로에도 넣지 않는다.
 *
 * ## 어디서 나는 소리인가
 *
 * `/System/Library/Audio/UISounds/` 안의 `.caf` — iOS 자신이 쓰는 파일이다. 이 파일을 `AVAudioPlayer`로
 * 재생한다: 미디어 볼륨(옆면 버튼)을 따르고, `.ambient`라 무음 스위치를 지키며 듣던 음악을 끊지
 * 않는다(#54에서 확인한 길). 파일을 못 읽는 기기(샌드박스가 막는 날)에는 같은 소리의 시스템 사운드
 * ID로 `AudioServicesPlaySystemSound`를 부른다 — ID는 문서화되지 않았지만 십 년 넘게 그대로인
 * 것만 골랐다(1123 키보드 클릭 · 1103 Tink · 1104 Tock · 1004 SentMessage). 카메라 타이머·탭백은
 * ID를 모르니 그때는 Tink/Tock으로 대신한다. 처음(#53)에 합성했던 소리는 지웠다.
 *
 * 끄는 자리는 프로필의 설정 메뉴("효과음"). 기본은 켬 — 무음 스위치가 이미 있으니 두 번 묻지 않는다. */

import AudioToolbox
import AVFoundation
import SwiftUI

@MainActor
enum SoundEffects {
    /// 설정 토글의 키(`@AppStorage`). 값이 없으면 켬.
    static let enabledKey = "sound.enabled"

    static func tap() { play(.tap) }
    /// 카운트다운 — `last`는 마지막 숫자(1). 카메라 앱도 마지막 1초만 다른 소리를 낸다.
    static func tick(last: Bool) { play(last ? .tickLast : .tick) }
    static func pop() { play(.pop) }
    static func success() { play(.success) }

    /* 효과음 설정 자체를 켜고 끌 때. **`isEnabled` 게이트를 우회한다**(`force`) — 끄는 순간의
     * 확인음마저 안 나면 "꺼졌다"는 피드백이 없어, 방금 무엇을 눌렀는지 알 수 없다. iOS 스위치도
     * 조작 자체는 피드백을 준다. 무음 스위치는 `.ambient`라 그대로 존중한다. */
    static func toggle(on: Bool) { play(on ? .toggleOn : .toggleOff, force: true) }

    // MARK: -

    private enum Sound {
        case tap, tick, tickLast, pop, success, toggleOn, toggleOff

        /// `/System/Library/Audio/UISounds/` 안의 파일 이름.
        var file: String {
            switch self {
            case .tap: "key_press_click"
            case .tick: "camera_timer_countdown"
            case .tickLast: "camera_timer_final_second"
            case .pop: "acknowledgment_sent"
            case .success: "SentMessage"
            case .toggleOn: "Tink"
            case .toggleOff: "Tock"
            }
        }

        /// 파일을 못 읽을 때 — 같은(또는 가장 가까운) 소리의 시스템 사운드 ID.
        var fallbackID: SystemSoundID {
            switch self {
            case .tap: 1123
            case .tick, .tickLast: 1103
            case .pop, .toggleOn: 1103   // Tink
            case .success: 1004
            case .toggleOff: 1104        // Tock
            }
        }
    }

    /// 시뮬레이터는 iOS 루트가 `IPHONE_SIMULATOR_ROOT` 아래에 있다 — 기기와 같은 소리가 나게 맞춘다.
    private static let directory: URL = {
        var root = ""
        #if targetEnvironment(simulator)
        root = ProcessInfo.processInfo.environment["IPHONE_SIMULATOR_ROOT"] ?? ""
        #endif
        return URL(fileURLWithPath: root + "/System/Library/Audio/UISounds", isDirectory: true)
    }()
    private static var players: [Sound: AVAudioPlayer] = [:]

    private static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    private static func play(_ sound: Sound, force: Bool = false) {
        guard force || isEnabled else { return }
        guard let player = player(for: sound) else {
            AudioServicesPlaySystemSound(sound.fallbackID)
            return
        }
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
        let url = directory.appending(path: "\(sound.file).caf")
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
