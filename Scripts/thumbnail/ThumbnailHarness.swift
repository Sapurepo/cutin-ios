/* 임시 검증 하니스 — 앱 타깃에 넣어 한 번 돌리고 다시 뺀다.
 *
 * 대표 컷(§6.3)의 순수 함수 둘을 검사한다. 서버 왕복이 없어 스텁이 필요 없다
 * (`Scripts/geometry`와 같은 방식).
 *
 *   ① `Post.gridImageURL` — **배열 위치가 아니라 `cutIndex`로** 찾는지. 계약이 컷 배열의
 *      순서를 약속하지 않으므로, 서버가 순서를 바꿔 보내는 날 `cuts[n]`은 조용히 다른 컷을
 *      그린다. 폴백 사다리(지정 → 첫 컷 → 합성본 → nil)도 함께 본다.
 *   ② `Post.isPinned` — 서버가 준 `pinned`가 답이고, 없을 때만 대표 컷 인덱스로 가르는지.
 *
 * 고정 순서 검사는 없다 — 정렬이 서버로 넘어갔다(cutin-backend#15). `Post.pinnedFirst`도 함께
 * 사라졌다: 앱에서 다시 정렬하면 받아 온 페이지 안에서만 맞아 옛 고정 포스트가 뒤에 숨는다.
 *
 * 실행: SIMCTL_CHILD_THUMBNAIL_CHECK=1 로 앱을 띄우면 stdout에 결과를 뱉는다. 서명 불필요. */

#if DEBUG
import Foundation

@MainActor
enum ThumbnailHarness {
    static var isRequested: Bool {
        ProcessInfo.processInfo.environment["THUMBNAIL_CHECK"] == "1"
    }

    private static var failures = 0

    static func run() {
        checkGridImage()
        print("=== 결과: \(failures == 0 ? "전부 통과" : "실패 \(failures)건") ===")
        fflush(stdout)
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - ①② gridImageURL · isPinned

    private static func checkGridImage() {
        print("=== ① gridImageURL — cutIndex로 찾는다 · ② isPinned ===")

        /* 컷 배열을 **역순으로** 담는다. 배열 위치로 찾는 구현은 여기서 틀린 컷을 내놓는다 —
         * 순서대로 담으면 두 구현이 같은 답을 내서 검사가 아무것도 가르지 못한다. */
        let shuffled = post(cutIndexes: [3, 1, 0, 2], thumbnail: 2)
        expect(shuffled.gridImageURL?.absoluteString == "https://cut/2",
               "지정 인덱스를 cutIndex로 찾는다 (배열은 역순)",
               shuffled.gridImageURL?.absoluteString ?? "nil")

        let unspecified = post(cutIndexes: [3, 1, 0, 2], thumbnail: nil)
        expect(unspecified.gridImageURL?.absoluteString == "https://cut/0",
               "미지정이면 첫 컷(cutIndex 0) — 서버 기본과 같다",
               unspecified.gridImageURL?.absoluteString ?? "nil")

        // 지정 인덱스에 컷이 없다(계약 위반). 던지거나 비우지 않고 가장 앞 컷으로 내려간다.
        let missing = post(cutIndexes: [1, 2], thumbnail: 7)
        expect(missing.gridImageURL?.absoluteString == "https://cut/1",
               "없는 인덱스 → 가장 앞 컷", missing.gridImageURL?.absoluteString ?? "nil")

        let noCuts = post(cutIndexes: [], thumbnail: nil)
        expect(noCuts.gridImageURL?.absoluteString == "https://composed",
               "컷이 없으면 합성본", noCuts.gridImageURL?.absoluteString ?? "nil")

        let bare = post(cutIndexes: [], thumbnail: nil, composed: false)
        expect(bare.gridImageURL == nil, "아무것도 없으면 nil",
               bare.gridImageURL?.absoluteString ?? "nil")

        expect(post(cutIndexes: [0, 1], thumbnail: 1).isPinned, "첫 컷이 아닌 것을 지정하면 고정")
        expect(!post(cutIndexes: [0], thumbnail: nil).isPinned, "미지정은 고정이 아니다")
        /* 서버는 발행 시 미지정을 0으로 채운다 — 발행된 포스트는 전부 non-null이다. nil 검사로
         * 가르면 전 셀에 핀이 붙는다(2026-08-17 감사 B3). 0은 기본과 같은 그림이라 고정이 아니다. */
        expect(!post(cutIndexes: [0, 1], thumbnail: 0).isPinned,
               "0은 서버가 채우는 기본 — 고정이 아니다")
        /* 서버가 `pinned`를 주면(cutin-backend#14) 그 값이 답이다 — 대표 컷과 별개. 대표 컷 없이
         * 고정만 켤 수도, 대표 컷을 골랐지만 고정을 풀 수도 있다. */
        expect(post(cutIndexes: [0, 1], thumbnail: 0, pinned: true).isPinned,
               "pinned=true면 대표 컷이 기본이어도 고정")
        expect(!post(cutIndexes: [0, 1], thumbnail: 1, pinned: false).isPinned,
               "pinned=false면 대표 컷을 골랐어도 고정이 아니다")
    }

    // MARK: - 표본

    private static func post(name: String = "P", cutIndexes: [Int], thumbnail: Int?,
                             pinned: Bool? = nil, composed: Bool = true) -> Post {
        let template = Template(id: UUID(), code: "grid4", name: "네 컷", cutCount: 4,
                                aspectRatio: "1:1",
                                slots: [TemplateSlot(x: 0, y: 0, width: 1, height: 1)])
        return Post(
            id: UUID(),
            author: PostAuthor(id: UUID(), nickname: name, avatarUrl: nil),
            template: template, frame: nil,
            status: ServerEnum(.published), visibility: ServerEnum(.friends),
            caption: name, thumbnailCutIndex: thumbnail, pinned: pinned,
            cuts: cutIndexes.map { index in
                PostCut(cutIndex: index, media: media(url: "https://cut/\(index)"))
            },
            composed: composed ? media(url: "https://composed") : nil,
            publishedAt: "2026-08-14T00:00:00.000Z", createdAt: "2026-08-14T00:00:00.000Z",
            commentCount: 0,
            reactions: ReactionSummary(total: 0, counts: [], mine: nil),
            bookmarked: false
        )
    }

    private static func media(url: String) -> Media {
        Media(id: UUID(), kind: ServerEnum(.cut), url: url, width: 100, height: 100)
    }

    private static func expect(_ passed: Bool, _ name: String, _ detail: String = "") {
        if passed {
            print("PASS  \(name)")
        } else {
            failures += 1
            print("FAIL  \(name)\(detail.isEmpty ? "" : "  — \(detail)")")
        }
    }
}
#endif
