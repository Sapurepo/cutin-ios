/* 알림 설정 — 명세 §3.3(선호 시간대) · §8.3(설정).
 *
 * 온보딩(§3.3)에서 슬롯을 고르게 하지 않은 이유는 그 화면 주석에 있다 — 고르게 해도 알림이
 * 가지 않는 상태였고, 서버가 완료 시점에 기본값(`morning`)을 채운다. 그 결정은 그대로 두고
 * **바꾸고 싶을 때 오는 자리**만 만든다. 처음 쓰는 사람에게 시간대를 묻는 것보다 낫다.
 *
 * ## 슬롯을 비울 수 없다
 *
 * 서버가 `minItems: 1`이라 슬롯은 하나 이상이어야 한다. "알림 끄기"는 슬롯을 비우는 것이 아니라
 * `pushEnabled: false`다 — 그래서 마지막 하나는 꺼지지 않게 막고, 끄고 싶으면 위 토글을 쓰라고
 * 화면이 말한다. 400을 받아 문구를 띄우는 것보다 짧다.
 *
 * ## 아직 알림이 오지 않는다는 사실을 숨기지 않는다
 *
 * 자격(entitlement)과 서버 APNs 구현이 모두 남아 있다(`PushRegistrar` 머리말). 설정만 그럴듯하게
 * 두면 "설정했는데 왜 안 와요"가 된다. 권한이 없으면 그 사실을 그대로 적는다. */

import SwiftUI

struct NotificationSettingsView: View {
    @Environment(NotificationStore.self) private var store
    @Environment(PushRegistrar.self) private var push
    @Environment(\.palette) private var palette

    private var slots: Set<NotificationSlot> {
        Set(store.preferences?.slots.compactMap(\.known) ?? [])
    }

    private var pushEnabled: Bool { store.preferences?.pushEnabled ?? true }

    var body: some View {
        Form {
            Section {
                Toggle("알림 받기", isOn: Binding(
                    get: { pushEnabled },
                    set: { enabled in
                        Task {
                            await store.updatePreferences(
                                slots: Array(slots.isEmpty ? [.morning] : slots),
                                pushEnabled: enabled
                            )
                        }
                    }
                ))
                .disabled(store.isSavingPreferences || store.preferences == nil)
            } footer: {
                if push.authorization == .denied {
                    Text("기기에서 알림이 꺼져 있어요. 설정 앱에서 허용할 수 있어요")
                } else if push.authorization == .notDetermined {
                    Text("알림을 켜면 기기 권한을 한 번 물어봐요")
                }
            }

            Section {
                ForEach(NotificationSlot.allCases, id: \.self) { slot in
                    Toggle(slot.label, isOn: Binding(
                        get: { slots.contains(slot) },
                        set: { toggle(slot, on: $0) }
                    ))
                    .disabled(store.isSavingPreferences || !pushEnabled)
                }
            } header: {
                Text("받고 싶은 시간대")
            } footer: {
                Text("고른 시간대에 하루 한 번 컷을 남기라고 알려줘요. 최소 하나는 켜져 있어야 해요")
            }

            if let failure = store.failure {
                Text(failure)
                    .font(Typography.caption)
                    .foregroundStyle(palette.danger)
            }
        }
        .navigationTitle("알림")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.loadPreferences()
            await push.refreshAuthorization()
        }
        .onChange(of: pushEnabled) { _, enabled in
            // 켤 때만 권한을 묻는다 — 끄는 사람에게 권한 창을 띄우면 반대로 읽힌다.
            guard enabled, push.authorization == .notDetermined else { return }
            Task { await push.requestAuthorization() }
        }
    }

    private func toggle(_ slot: NotificationSlot, on: Bool) {
        var wanted = slots
        if on {
            wanted.insert(slot)
        } else {
            // 마지막 하나는 끄지 않는다 — 서버가 거절한다.
            guard wanted.count > 1 else { return }
            wanted.remove(slot)
        }
        Task { await store.updatePreferences(slots: Array(wanted), pushEnabled: pushEnabled) }
    }
}

extension NotificationSlot {
    /// 시각은 서버 `slotStartHours`가 정한다 — 여기 적는 것은 그 값의 사본이 아니라 안내 문구다.
    var label: String {
        switch self {
        case .morning: return "아침 (8시)"
        case .lunch: return "점심 (12시)"
        case .evening: return "저녁 (18시)"
        case .night: return "밤 (21시)"
        }
    }
}
