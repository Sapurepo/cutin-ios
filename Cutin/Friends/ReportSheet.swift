/* 신고 — 명세 §1-7(운영·법적 요구).
 *
 * 포스트·댓글·사용자 셋 다 같은 엔드포인트를 쓰므로(`POST /reports`) 화면도 하나다.
 * 대상 종류만 다르게 넘긴다.
 *
 * ## 접수만 하고 결과를 말하지 않는다
 *
 * 서버가 `status`(pending/reviewing/resolved)를 돌려주지만 화면은 "접수했어요"만 말한다.
 * 처리 상태를 보여주려면 신고 내역 화면이 있어야 하고, 그건 어드민이 실제로 처리하기 시작한
 * 뒤의 일이다. 지금 상태를 보여주면 영원히 `pending`인 목록을 만들게 된다. */

import SwiftUI

struct ReportSheet: View {
    let targetType: ReportTargetType
    let targetId: UUID

    @Environment(SocialStore.self) private var social
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var reason: ReportReason = .spam
    @State private var detail = ""
    @State private var isSending = false
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("이유") {
                    Picker("이유", selection: $reason) {
                        ForEach(ReportReason.allCases, id: \.self) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("자세한 내용 (선택)") {
                    TextField("무슨 일이 있었나요", text: $detail, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let failure {
                    Text(failure)
                        .font(Typography.caption)
                        .foregroundStyle(palette.danger)
                }
            }
            .navigationTitle("신고하기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSending ? "보내는 중…" : "보내기") { Task { await send() } }
                        .disabled(isSending)
                }
            }
        }
    }

    private func send() async {
        isSending = true
        failure = nil
        defer { isSending = false }

        do {
            try await social.report(targetType: targetType, targetId: targetId,
                                    reason: reason, detail: detail)
            dismiss()
        } catch {
            // 서버 문구를 그대로 쓴다 — 중복 신고 같은 거절 이유를 앱이 다시 쓰지 않는다.
            failure = (error as? APIError)?.serverMessage ?? "신고를 접수하지 못했어요"
        }
    }
}

extension ReportReason {
    var label: String {
        switch self {
        case .spam: return "스팸이에요"
        case .abuse: return "괴롭힘이나 욕설이에요"
        case .sexualContent: return "선정적인 내용이에요"
        case .copyright: return "저작권을 침해했어요"
        case .other: return "다른 이유예요"
        }
    }
}
