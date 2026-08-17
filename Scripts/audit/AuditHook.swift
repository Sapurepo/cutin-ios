/* AUDIT-HOOK (커밋 금지) — UI 감사용. 환경변수로 화면을 바로 연다.
 *
 *   AUDIT_SCREEN = feed | notifications | postDetail | userProfile | tips | catalog
 *                | notificationSettings | friends | profile | archive
 *                | captureSetup | camera | template | filter | finish
 *   AUDIT_POST / AUDIT_USER = UUID
 *
 * template/filter/finish는 호스트가 Documents/Drafts/cut-0..3.jpg를 미리 넣어 둔다. */

#if DEBUG
import SwiftUI

@MainActor
enum AuditHook {
    /// 빈 값은 미설정으로 본다 — 셸이 `VAR=${X:-}`로 넘기면 빈 문자열이 들어온다.
    private static var env: [String: String] {
        ProcessInfo.processInfo.environment.filter { !$0.value.isEmpty }
    }
    static var screen: String? { env["AUDIT_SCREEN"] }

    static var routes: [Route] {
        let post = UUID(uuidString: env["AUDIT_POST"] ?? "") ?? UUID()
        let user = UUID(uuidString: env["AUDIT_USER"] ?? "") ?? UUID()
        switch screen {
        case "notifications": return [.notifications]
        case "postDetail": return [.postDetail(post)]
        case "userProfile": return [.userProfile(user)]
        case "notificationSettings": return [.notificationSettings]
        case "tips": return [.tips]
        case "catalog": return [.designCatalog]
        default: return []
        }
    }

    static func apply(coordinator: AppCoordinator, flow: CaptureFlow, catalog: TemplateCatalog) async {
        switch screen {
        case "friends": coordinator.select(.friends, hasDraft: false)
        case "profile": coordinator.select(.profile, hasDraft: false)
        case "archive": coordinator.select(.archive, hasDraft: false)
        case "captureSetup":
            coordinator.startCapture()
        case "camera":
            coordinator.startCapture()
            coordinator.capturePath = [.camera]
        case "template", "filter", "finish":
            await catalog.loadIfNeeded()
            // RootView의 loadIfNeeded와 겹치면 바로 돌아온다 — 실제로 채워질 때까지 기다린다.
            for _ in 0..<50 where catalog.templates.isEmpty || catalog.frames.isEmpty {
                try? await Task.sleep(for: .milliseconds(100))
            }
            let template = catalog.templates.first { $0.code == (env["AUDIT_TEMPLATE"] ?? "grid4") }
            let frame = catalog.frames.first { $0.code == (env["AUDIT_FRAME"] ?? "white") }
            let drafts = DraftStore()
            try? drafts.save(DraftStore.Draft(
                createdAt: Date().addingTimeInterval(-20 * 3600), mode: .single, // 컷 파일보다 앞서야 한다(cp는 생성 시각을 보존)
                cutCount: template?.cutCount ?? 4, template: template, frame: frame,
                filterID: .original, caption: env["AUDIT_CAPTION"] ?? ""))
            flow.refreshDraft()
            guard await flow.resumeDraft() else { return }
            // 루트를 카메라가 아니라 설정 화면으로 — 시뮬레이터는 카메라 권한 대화상자가 막는다.
            coordinator.startCapture()
            switch screen {
            case "filter": coordinator.capturePath = [.template, .filter]
            case "finish": coordinator.capturePath = [.template, .filter, .finish]
            default: coordinator.capturePath = [.template]
            }
        default: break
        }
    }
}
#endif
