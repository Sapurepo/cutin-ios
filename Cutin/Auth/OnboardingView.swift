/* 온보딩 — 명세 §3. **닉네임과 프로필 사진**만 만든다.
 *
 * §3은 다섯 단계(닉네임·친구목록·알림 슬롯·프로필 사진·팁 화면)를 적어 두었지만, 지금 만들 수
 * 있는 것은 닉네임과 프로필 사진 둘뿐이다:
 *
 * - **§3.2 친구목록** — 명세에서 🔴(실현성 미확인)이고 서버에 연락처 매칭 경로가 없다.
 * - **§3.3 알림 슬롯** — 고르게 해도 알림이 가지 않는다(푸시 인프라 미정). 서버가 온보딩 완료
 *   시점에 기본 슬롯을 채우므로(`completeOnboarding`), 지키지 못할 약속을 화면에 만들지 않는다.
 * - **§3.4 프로필 사진** — 넣었다. 업로드 계층이 생겼고, `PhotosPicker`는 사진 권한 키가
 *   필요 없다(0.1.0에서 미룬 근거였던 "읽기 권한 키"는 사실이 아니었다). 건너뛸 수 있다 —
 *   고르지 않으면 서버가 기본 아바타를 쓴다.
 * - **§3.5 팁 화면** — 보여줄 팁이 정해지지 않았다. 세 장을 지어내면 그게 곧 거짓말이다.
 *
 * 그래서 단계 표시(1/5 같은 것)도 두지 않았다. 화면 하나로 끝나는 흐름에 진행 막대를 그리면
 * 뒤에 무언가 더 있는 것처럼 보인다. 사진과 이름을 한 화면에 둔 것도 같은 이유다 — 사진 한 장
 * 때문에 화면을 하나 더 만들면 "건너뛰기"라는 결정을 사용자에게 한 번 더 시킨다.
 *
 * ## 이 화면이 서버와 나누는 일
 *
 * 판정은 **전부 서버가 한다.** 길이·문자 규칙(`2~16자`, `^[가-힣a-zA-Z0-9_]+$`)을 여기 옮겨
 * 적으면 서버가 규칙을 바꿀 때 두 곳이 갈린다. 화면은 사유(enum)에 문구를 붙이는 일만 한다 —
 * 확인 API는 `reason`만 주고 문장을 주지 않기 때문이다. */

import SwiftUI

struct OnboardingView: View {
    @Environment(AuthSession.self) private var session
    @Environment(\.palette) private var palette

    @State private var nickname: String
    @State private var availability: NicknameAvailability?
    @State private var isChecking = false
    @FocusState private var isFocused: Bool

    /// 서버에 이미 저장된 닉네임. 저장은 됐는데 온보딩이 닫히지 않은 채 다시 들어온 경우다.
    private let saved: String?

    init(saved: String?) {
        self.saved = saved
        _nickname = State(initialValue: saved ?? "")
    }

    private var trimmed: String { nickname.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            heading
            avatar.padding(.top, Spacing.x6)
            field.padding(.top, Spacing.x5)
            hintLine.padding(.top, Spacing.x2)
            Spacer()
            if let failure = session.failure { failureNotice(failure) }
            startButton.padding(.top, Spacing.x3)
            Spacer().frame(height: Spacing.x8)
        }
        .padding(.horizontal, Spacing.x6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.bg)
        /* 입력이 멈출 때만 확인한다. `.task(id:)`는 값이 바뀌면 이전 작업을 취소하므로
         * 아래 `Task.sleep`이 디바운스가 된다 — 타이머를 따로 들 필요가 없다. */
        .task(id: nickname) { await check() }
        .onAppear { isFocused = true }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: Spacing.x2) {
            // 이 크기를 쓰는 곳이 여기뿐이라 토큰으로 승격하지 않는다(호출부 2곳 규칙).
            Text("어떻게 불러드릴까요?")
                .font(Typography.font(.body, .bold, size: 22))
                .foregroundStyle(palette.textPrimary)
            Text("컷을 남기면 이 이름으로 보여요")
                .font(Typography.bodyText)
                .foregroundStyle(palette.textSecondary)
        }
    }

    /* 사진은 선택이다. 안내 문구를 따로 달지 않았다 — 카메라 배지가 누를 수 있다는 표시이고,
     * "건너뛸 수 있어요"를 적으면 필수인 줄 알았을 사람에게만 도움이 된다. */
    private var avatar: some View {
        AvatarPicker(url: avatarUrl, nickname: trimmed.isEmpty ? nil : trimmed)
            .frame(maxWidth: .infinity)
    }

    private var avatarUrl: String? {
        if case .signedIn(let profile) = session.phase { return profile.avatarUrl }
        return nil
    }

    private var field: some View {
        TextField("닉네임", text: $nickname)
            .font(Typography.headline)
            .foregroundStyle(palette.textPrimary)
            .focused($isFocused)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .onSubmit(submit)
            .padding(Spacing.x4)
            .background(palette.surface, in: .rect(cornerRadius: Radius.md))
            .tokenBorder(RoundedRectangle(cornerRadius: Radius.md), color: borderColor)
    }

    /* 확인 결과 한 줄. 자리를 항상 차지하게 두어 문구가 나타날 때 아래가 밀리지 않는다.
     * 확인 중에는 이전 결과를 지운다 — 옛 판정을 새 입력에 대한 답처럼 보여주면 안 된다. */
    private var hintLine: some View {
        Text(hint)
            .font(Typography.caption)
            .foregroundStyle(hintColor)
            .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
            .animation(.easeOut(duration: Duration.fast), value: hint)
    }

    private func failureNotice(_ text: String) -> some View {
        Text(text)
            .font(Typography.caption)
            .foregroundStyle(palette.danger)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /* 확인이 끝나지 않았거나 실패했어도 누를 수 있게 둔다. 확인은 **참고**일 뿐이고, 진짜 판정은
     * 저장이다 — 확인과 저장 사이에 남이 같은 이름을 채 갈 수도 있다. 오프라인이라 확인이
     * 실패한 사용자를 버튼조차 못 누르게 막으면, 고칠 수 없는 화면에 가둔다. */
    private var startButton: some View {
        Button(action: submit) {
            Text(session.isAuthenticating ? "저장 중…" : "시작하기").primaryGlassLabel()
        }
        .primaryGlassButton(tint: palette.accent)
        .disabled(trimmed.isEmpty || session.isAuthenticating || availability?.available == false)
    }

    // MARK: - 동작

    private func submit() {
        guard !trimmed.isEmpty else { return }
        isFocused = false
        Task { await session.completeOnboarding(nickname: trimmed) }
    }

    private func check() async {
        availability = nil
        // 취소된 이전 확인이 "확인 중…"을 켜 둔 채 끝났을 수 있다 — 새 확인은 꺼진 상태에서 시작한다.
        isChecking = false
        guard !trimmed.isEmpty else { return }
        /* 내 이름은 묻지 않는다. 서버의 가용성 검사는 본인을 제외하지 않아 저장된 닉네임 그대로면
         * "이미 누군가 쓰고 있어요"가 뜨고 시작 버튼이 잠긴다 — 이름을 바꾸지 않으면 나갈 수
         * 없는 화면이 된다(2026-08-17 감사 B5). 저장 경로(`completeOnboarding`)는 같은 이름이면
         * PATCH를 건너뛰므로 여기서도 건너뛰는 것이 맞다. 대소문자는 서버가 lower로 비교한다. */
        if let saved, trimmed.lowercased() == saved.lowercased() { return }

        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }

        isChecking = true
        /* 실패는 삼킨다. 확인은 참고이고 문구를 띄울 자리가 이 줄뿐이라, 여기에 네트워크 오류를
         * 쓰면 아직 저장을 시도하지도 않은 사용자에게 실패를 알리는 꼴이 된다. */
        let result = try? await session.checkNickname(trimmed)

        // 취소됐으면 아무것도 건드리지 않는다 — 뒤늦게 끝난 옛 확인이 새 확인의 표시를 지운다.
        guard !Task.isCancelled else { return }
        availability = result
        isChecking = false
    }

    // MARK: - 표시

    private var hint: String {
        if isChecking { return "확인 중…" }
        guard let availability else { return " " }
        guard !availability.available else { return "쓸 수 있는 이름이에요" }

        /* `known`이 nil이면 서버가 사유를 새로 추가한 것이다. 그때도 "쓸 수 없다"는 사실은
         * 맞으므로 일반 문구로 떨어진다 — 여기서 던지면 화면이 빈다. */
        switch availability.reason?.known {
        case .invalidFormat: return "한글·영문·숫자·밑줄 2~16자로 지어주세요"
        case .taken: return "이미 누군가 쓰고 있어요"
        case .forbiddenWord, nil: return "쓸 수 없는 이름이에요"
        }
    }

    private var hintColor: Color {
        guard let availability, !isChecking else { return palette.textSecondary }
        return availability.available ? palette.textSecondary : palette.danger
    }

    private var borderColor: Color {
        guard let availability, !isChecking, !availability.available else {
            return isFocused ? palette.borderStrong : palette.border
        }
        return palette.danger
    }
}
