/* 서버 템플릿·프레임 목록 — 0.1.0의 로컬 `Templates`·`FrameSkins` 레지스트리를 대체한다.
 *
 * 두 목록을 한 객체가 갖는 이유: 편집 1단계가 둘을 함께 쓰고(배치 칩 + 외형 칩), 촬영 설정이
 * 고를 수 있는 컷 수도 템플릿 목록에서 유도된다. 따로 두면 화면마다 "둘 다 왔는지" 확인해야 한다.
 *
 * **둘 다 인증이 필요하다**(`GET /templates`·`GET /frames`가 `[auth]`). 그래서 로그인 뒤에
 * 불러야 하고, 로그인 전에는 아무것도 고를 수 없다 — 촬영 자체가 로그인 뒤의 일이라 맞다.
 *
 * 캐시를 두지 않는다. 목록이 8+8개고 앱 실행당 한 번 받으므로, 파일 캐시를 만들면 "서버가
 * 템플릿을 고쳤는데 앱은 옛것을 쓴다"는 문제를 새로 얻는다. 오프라인 촬영은 0.2.0 범위 밖이다. */

import Foundation
import Observation

@MainActor
@Observable
final class TemplateCatalog {
    /// 그릴 수 있는 템플릿만. 노출 순서는 서버가 준 배열 순서다.
    private(set) var templates: [Template] = []
    private(set) var frames: [Frame] = []
    private(set) var isLoading = false
    private(set) var failure: String?

    @ObservationIgnored private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    var isReady: Bool { !templates.isEmpty && !frames.isEmpty }

    /* 기본값은 **서버 배열의 첫 항목**이다. 로컬에 기본 코드(`basic`·`grid4`)를 박으면 서버가
     * 순서나 구성을 바꿔도 앱이 옛 판단을 유지하고, 그 코드가 사라지면 기본값이 없어진다.
     * 서버가 `sortOrder`로 순서를 정해 내려보내므로 첫 항목이 서버의 의도다. */
    var defaultFrame: Frame? { frames.first }

    /// 고를 수 있는 컷 수 — 템플릿 목록에서 유도한다. 열거형으로 박지 않는 이유가 이것이다.
    var cutCounts: [Int] { Array(Set(templates.map(\.cutCount))).sorted() }

    func templates(cutCount: Int) -> [Template] {
        templates.filter { $0.cutCount == cutCount }
    }

    func defaultTemplate(cutCount: Int) -> Template? {
        templates(cutCount: cutCount).first
    }

    /* 셸이 뜰 때 부른다. 이미 받아 뒀으면 아무것도 하지 않는다 — `.task`는 뷰가 다시 나타날 때
     * 또 도는데, 그때마다 다시 받으면 편집 중에 목록이 갈릴 수 있다. 실패했을 때만 다시 시도한다. */
    func loadIfNeeded() async {
        guard !isReady else { return }
        await load()
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        failure = nil
        defer { isLoading = false }

        do {
            let fetchedTemplates: TemplatesResponse = try await client.send(
                .get, "/templates", as: TemplatesResponse.self
            )
            let fetchedFrames: FramesResponse = try await client.send(
                .get, "/frames", as: FramesResponse.self
            )

            /* 못 그리는 템플릿은 뺀다. 서버 시드가 잘못돼도(슬롯 겹침·컷 수 불일치) 편집 화면이
             * 죽지 않고 그 템플릿만 사라진다 — 0.1.0은 배치가 로컬 상수여서 `assert`로 잡았지만
             * 지금은 남의 데이터다. */
            let renderable = fetchedTemplates.items.filter(CutGeometry.isRenderable)
            let dropped = fetchedTemplates.items.count - renderable.count
            if dropped > 0 {
                // 조용히 사라지면 "왜 템플릿이 적지"를 쫓을 단서가 없다.
                print("[TemplateCatalog] 그릴 수 없는 템플릿 \(dropped)개를 제외했습니다")
            }

            templates = renderable
            frames = fetchedFrames.items
            if templates.isEmpty || frames.isEmpty {
                failure = "템플릿을 받지 못했어요. 잠시 후 다시 시도해주세요"
            }
        } catch {
            failure = message(for: error)
        }
    }

    private func message(for error: any Error) -> String {
        switch error {
        case APIError.transport:
            return "서버에 연결할 수 없어요. 잠시 후 다시 시도해주세요"
        case APIError.server(_, _, let message, _):
            return message
        default:
            return "템플릿을 받지 못했어요. 잠시 후 다시 시도해주세요"
        }
    }
}
