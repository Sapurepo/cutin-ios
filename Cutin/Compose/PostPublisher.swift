/* 발행 파이프라인 — 촬영 결과를 서버 포스트로 만든다.
 *
 *   ① `POST /posts`                draft 생성 (템플릿을 정한다)
 *   ② 컷 N장 업로드                 각각 `MediaUploader`의 왕복 셋
 *   ③ `PATCH /posts/{id}`          컷·프레임·캡션·대표 컷을 붙인다
 *   ④ 합성본 업로드                 `kind: composed`
 *   ⑤ `POST /posts/{id}/publish`   발행
 *
 * 왕복이 컷 4장 기준 **열여섯 번**이다. 화면에 늘어놓을 수 없고, 중간에 끊겼을 때 어디까지
 * 갔는지 사용자가 알아야 한다. 그래서 진행 단계를 값으로 들고 화면은 그것만 그린다.
 *
 * ## 서버 draft는 계정당 하나다
 *
 * `posts`에 작성자별 draft 유니크 제약이 있어 두 번째 `POST /posts`는 `DRAFT_ALREADY_EXISTS`로
 * 거절된다. 발행이 중간에 끊기면 서버에 draft가 남으므로, **409를 만나면 그 draft를 이어 쓴다.**
 * 새로 만들 수 없으니 지우고 다시 만드는 방법도 있지만, 그러면 이미 올라간 컷을 버리게 된다.
 * `PATCH`의 `cuts`는 통째로 교체(`replaceCuts`)라 이어 쓰는 쪽이 항상 옳은 상태로 수렴한다.
 *
 * ## 컷을 하나씩 올리는 이유
 *
 * 동시에 올리면 빠르지만, 12MP JPEG 여섯 장을 셀룰러에서 한꺼번에 밀면 타임아웃이 겹쳐
 * "몇 장은 올라가고 몇 장은 아닌" 상태가 된다. 순서대로 올리면 진행률이 정직해지고,
 * 실패해도 어디서 멈췄는지가 분명하다. */

import UIKit

@MainActor
@Observable
final class PostPublisher {
    /// 지금 어느 왕복에 있는지. 화면은 이 값의 `label`만 읽는다.
    enum Step: Equatable {
        case idle
        case creatingDraft
        case uploadingCuts(done: Int, total: Int)
        case attachingCuts
        case uploadingComposed
        case publishing

        var label: String? {
            switch self {
            case .idle: return nil
            case .creatingDraft: return "준비 중…"
            case .uploadingCuts(let done, let total): return "컷 올리는 중 \(done)/\(total)"
            case .attachingCuts: return "컷 붙이는 중…"
            case .uploadingComposed: return "완성본 올리는 중…"
            case .publishing: return "발행 중…"
            }
        }
    }

    private(set) var step: Step = .idle

    @ObservationIgnored private let client: APIClient
    @ObservationIgnored private lazy var uploader = MediaUploader(client: client)

    init(client: APIClient) {
        self.client = client
    }

    var isPublishing: Bool { step != .idle }

    struct Request {
        var template: Template
        var frame: Frame?
        /// 촬영한 컷 원본. 순서가 곧 `cutIndex`다.
        var cuts: [UIImage]
        /// 구워진 합성본. 서버는 다시 그리지 않고 이 바이트를 그대로 보관한다.
        var composed: UIImage
        var caption: String
        var visibility: PostVisibility
        /// 대표 컷. nil이면 서버가 첫 컷을 쓴다(§6.3).
        var thumbnailCutIndex: Int?
    }

    func publish(_ request: Request) async throws -> Post {
        step = .creatingDraft
        defer { step = .idle }

        let draft = try await draft(templateId: request.template.id)

        var cuts: [PatchPostBody.CutInput] = []
        for (index, image) in request.cuts.enumerated() {
            step = .uploadingCuts(done: index, total: request.cuts.count)
            let media = try await uploader.upload(image, kind: .cut)
            cuts.append(PatchPostBody.CutInput(cutIndex: index, mediaId: media.id))
        }

        /* 캡션·대표 컷을 **발행 요청이 아니라 여기서** 붙인다. 발행이 끊겨도 draft에 남아,
         * 다시 시도할 때 사용자가 쓴 글이 사라지지 않는다. 발행 요청에도 실을 수 있지만
         * (`PublishPostBody`), 그러면 실패한 순간 캡션이 어디에도 없다. */
        step = .attachingCuts
        _ = try await client.send(
            .patch, "/posts/\(draft.id.path)",
            body: PatchPostBody(
                // 이어 쓴 draft는 다른 템플릿일 수 있다. 컷 수 검사가 이 값 기준이라 함께 보낸다.
                templateId: request.template.id,
                frameId: request.frame.map { .value($0.id) } ?? .null,
                caption: request.caption.isEmpty ? .null : .value(request.caption),
                thumbnailCutIndex: request.thumbnailCutIndex.map { .value($0) },
                cuts: cuts
            ),
            as: Post.self
        )

        step = .uploadingComposed
        let composed = try await uploader.upload(request.composed, kind: .composed)

        step = .publishing
        return try await client.send(
            .post, "/posts/\(draft.id.path)/publish",
            body: PublishPostBody(
                composedMediaId: composed.id,
                visibility: ServerEnum(request.visibility),
                // 대표 컷을 직접 골랐으면 고정(0.3.0 제품 결정) — 첫 컷을 골라도 고정이다.
                pinned: request.thumbnailCutIndex != nil
            ),
            as: Post.self
        )
    }

    /* draft를 얻는다. 이미 있으면 그것을 쓴다.
     *
     * `POST`를 먼저 시도하고 409에서 `GET`으로 넘어간다 — 순서를 뒤집어 `GET`부터 하면
     * 정상 경로(draft 없음)가 404 한 번을 항상 낭비한다.
     *
     * 코드가 아니라 **상태(409)**로 가른다. 서버가 내는 코드는 `CONFLICT`가 아니라
     * `DRAFT_ALREADY_EXISTS`다 — 도메인 코드라 앱의 일반 코드 열거형에 없다. */
    private func draft(templateId: UUID) async throws -> Post {
        do {
            return try await client.send(
                .post, "/posts", body: CreatePostBody(templateId: templateId), as: Post.self
            )
        } catch let error as APIError where error.isConflict {
            return try await client.send(.get, "/posts/draft", as: Post.self)
        }
    }
}
