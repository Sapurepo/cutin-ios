/* 서버 계약 타입 — `cutin-backend`가 생성한 `openapi.json`(NestJS + nestjs-zod)에서 옮겼다.
 *
 * **손으로 지어낸 타입이 아니다.** 서버의 Zod 스키마가 OpenAPI로 산출되고, 그 스펙에서
 * 필드명·필수 여부·nullable·열거형을 그대로 베꼈다. 추측한 필드는 없다.
 *
 * 규칙 셋:
 *
 * 1. **nullable과 optional을 구별한다.** 서버 Zod에서 `.nullable()`은 "키는 있고 값이 null",
 *    `.optional()`은 "키가 없을 수 있음"이다. Swift에서는 둘 다 `?`가 되지만 인코딩이 다르다 —
 *    nullable은 `null`을 실어야 하고 optional은 키를 빼야 한다. 요청 바디(`Encodable`)에서
 *    이 차이가 실제로 갈린다(§`PatchPostBody`).
 * 2. **열거형을 닫지 않는다.** 서버가 `postStatuses`에 값을 추가하면 구버전 앱이 디코드에
 *    실패해 화면 전체가 빈다. 원시값 보존형(`ServerEnum`)으로 받아 모르는 값은 통과시킨다.
 * 3. **날짜를 `Date`로 받지 않는다.** 서버는 `z.string()`으로 내려보내고 형식을 계약에 적지
 *    않았다. `String`으로 받아 표시 계층에서 파싱한다 — 형식이 어긋나도 포스트 전체가
 *    사라지지 않는다.
 *
 * 이름은 서버 DTO를 따르되 `Dto` 접미사는 뺐다(Swift에서는 타입 위치가 역할을 말한다).
 */

import Foundation

// MARK: - 열거형 (원시값 보존)

/* 서버 열거형을 받는 래퍼. 아는 값은 `known`으로, 모르는 값은 원시 문자열로 남는다.
 *
 * `enum: String, Codable`을 그대로 쓰면 서버가 값을 하나 추가하는 순간 구버전 앱의
 * 디코드가 던지고, `PostPage` 하나가 통째로 실패해 피드가 빈다. 반응 종류처럼
 * 늘어날 게 뻔한 필드에서 이 사고가 난다. */
struct ServerEnum<Known: RawRepresentable & Sendable>: Codable, Hashable, Sendable
where Known.RawValue == String, Known: Hashable {
    let raw: String

    var known: Known? { Known(rawValue: raw) }

    init(_ known: Known) { self.raw = known.rawValue }

    init(from decoder: any Decoder) throws {
        raw = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(raw)
    }
}

enum MediaKind: String, Sendable, Hashable {
    case cut, composed, avatar
}

enum PostStatus: String, Sendable, Hashable {
    case draft, published, deleted
}

enum PostVisibility: String, Sendable, Hashable, CaseIterable {
    case friends, `public`, `private`
}

enum ReactionType: String, Sendable, Hashable {
    case like, love, haha, wow, sad
}

enum OAuthProvider: String, Sendable, Hashable {
    case google, kakao
}

/// 업로드 가능한 MIME. 서버 `allowedMimes`와 같은 순서다.
enum UploadMime: String, Sendable, Hashable {
    case jpeg = "image/jpeg"
    case png = "image/png"
    case heic = "image/heic"
}

// MARK: - 인증

struct OAuthLoginBody: Encodable, Sendable {
    /* **provider마다 토큰 종류가 다르다.** 서버 `oauthVerifier.ts`가
     * google은 `id_token`을 Google JWKS로 검증하고(audience = 서버의 GOOGLE_CLIENT_ID),
     * kakao는 `access_token`을 `kapi.kakao.com/v2/user/me`의 Bearer로 쓴다.
     * 필드 이름이 둘 다 `token`이라 잘못 보내면 401만 돌아오고 원인이 드러나지 않는다. */
    let token: String
}

struct LoginResponse: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String
    /// 액세스 토큰 수명(초).
    let expiresIn: Int
    /// false면 닉네임 온보딩으로 보내야 한다.
    let onboardingCompleted: Bool
}

struct RefreshBody: Encodable, Sendable {
    let refreshToken: String
}

/// 재발급 응답에는 `onboardingCompleted`가 없다 — 로그인 응답과 다른 타입이다.
struct TokensResponse: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
}

/* 경로에 실을 식별자 표기.
 *
 * `UUID.uuidString`은 **대문자**를 낸다. 서버는 정규형(소문자)으로 주고, postgres의 `uuid`
 * 컬럼은 둘 다 받으므로 지금은 어느 쪽이든 붙는다. 그래도 서버가 준 표기로 되돌려 보내는 편이
 * 맞다 — 로그·캐시 키가 서버와 같아지고, uuid 컬럼이 아닌 식별자(스토리지 키 등)가 경로에
 * 들어오는 날 조용히 깨지지 않는다. */
extension UUID {
    var path: String { uuidString.lowercased() }
}

// MARK: - 사용자

struct UserProfile: Decodable, Sendable, Equatable {
    let id: UUID
    /// 온보딩 전에는 null이다.
    let nickname: String?
    let avatarUrl: String?
    let timezone: String
    let onboardingCompleted: Bool
}

struct UpdateMeBody: Encodable, Sendable {
    /* 셋 다 optional이다 — 서버가 **보낸 키만** 반영한다.
     * `avatarMediaId`는 optional이면서 nullable이라 "안 건드림"과 "아바타 지움"이 다르다.
     * 그 구분을 `Field`로 표현한다(§`Field`). */
    var nickname: String?
    var timezone: String?
    var avatarMediaId: Field<UUID>?
}

struct NicknameAvailability: Decodable, Sendable {
    enum Reason: String, Sendable, Hashable {
        case invalidFormat, forbiddenWord, taken
    }

    let available: Bool
    /// `available`이 true면 null이다.
    let reason: ServerEnum<Reason>?
}

// MARK: - 템플릿

/// 컷 하나가 놓일 자리. 그리드 영역 기준 0~1 비율이다.
struct TemplateSlot: Codable, Sendable, Hashable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

/* 컷 수와 배치의 **유일한 출처**. 0.1.0의 로컬 `CutCount`·`CutLayout`을 대체한다.
 * 서버 `postsController.ts`: "컷 수와 레이아웃은 서버가 정의한다. 클라이언트가 컷 수를
 * 가정하지 않는다." */
struct Template: Codable, Sendable, Hashable {
    let id: UUID
    /// 안정 식별자(`single`·`grid4`…). id는 환경마다 다르므로 코드에서 특정할 때 이걸 쓴다.
    let code: String
    let name: String
    let cutCount: Int
    /// `"3:4"` 형태. 그리드 영역의 비율이다(프레임 여백 제외 — cutin-backend#11 C).
    let aspectRatio: String
    let slots: [TemplateSlot]
}

struct TemplatesResponse: Decodable, Sendable {
    let items: [Template]
}

// MARK: - 프레임(외형)

/* 합성 결과의 겉모습 — 프레임 색·여백·컷 라운딩·푸터. 서버가 소유한다(`GET /frames`).
 *
 * **길이는 캔버스 폭 대비 비율이다.** 0.1.0은 이 값들을 360pt 설계 폭 기준 px으로 갖고
 * 출력 폭에 비례 확대했는데, 서버가 px으로 주면 어느 폭 기준인지가 계약에서 빠진다.
 * 서버 시드가 `ratio(px) = px / 360`으로 같은 값을 비율로 바꿔 담았다.
 *
 * 색은 `"#RRGGBB"` 문자열이다. **UI 테마 색이 아니라 콘텐츠 색이다** — 합성본은 한 번 구워지면
 * 파일로 남으므로 사용자가 라이트/다크를 바꿔도 같은 그림이어야 한다. */
struct Frame: Codable, Sendable, Hashable {
    enum Footer: String, Sendable, Hashable {
        /// 하단 CUTIN 로고 + 날짜 스탬프. 로고 문자열과 서체는 클라이언트 자산이다.
        case logoDate
    }

    let id: UUID
    /// 안정 식별자(`basic`·`white`…). id는 환경마다 다르다.
    let code: String
    let name: String
    /// 프레임 배경 `#RRGGBB`
    let background: String
    /// 푸터 스탬프·빈 슬롯 표시 `#RRGGBB`
    let foreground: String
    let padding: Double
    let gutter: Double
    let cellRadius: Double
    /// null이면 푸터를 그리지 않는다.
    let footer: ServerEnum<Footer>?
}

/* 페이징이 없다 — 목록이 8종이라 서버가 커서를 두지 않았다. 활성 항목만 내려오고
 * **배열이 이미 노출 순서로 정렬돼 있다**(`isActive`·`sortOrder`가 계약에 없는 이유다). */
struct FramesResponse: Decodable, Sendable {
    let items: [Frame]
}

// MARK: - 미디어

struct CreateUploadBody: Encodable, Sendable {
    let kind: ServerEnum<MediaKind>
    let mime: ServerEnum<UploadMime>
}

/* 업로드 목적지. **presigned S3가 아니라 서버 자신의 엔드포인트다** —
 * `PUT /media/content/{path}`가 Bearer를 요구한다(`[auth]`). 따라서 이 `url`로 보낼 때도
 * 인증 헤더를 붙여야 하고, `headers`에 온 값을 덮어쓰지 말고 합쳐야 한다.
 * 스토리지 벤더가 확정되면 외부 URL로 바뀔 수 있으므로 `url`을 절대/상대 양쪽으로 해석한다. */
struct UploadTarget: Decodable, Sendable {
    let mediaId: UUID
    let url: String
    /// 스펙상 `PUT` 하나뿐이지만 서버가 값으로 내려보내므로 값으로 받는다.
    let method: String
    let headers: [String: String]
}

struct CompleteUploadBody: Encodable, Sendable {
    let width: Int
    let height: Int
}

struct Media: Decodable, Sendable, Hashable {
    let id: UUID
    let kind: ServerEnum<MediaKind>
    let url: String
    /// `complete` 호출 전에는 null이다.
    let width: Int?
    let height: Int?
}

// MARK: - 포스트

struct PostAuthor: Decodable, Sendable, Hashable {
    let id: UUID
    let nickname: String?
    let avatarUrl: String?
}

struct PostCut: Decodable, Sendable, Hashable {
    let cutIndex: Int
    let media: Media
}

struct ReactionSummary: Decodable, Sendable, Hashable {
    struct Count: Decodable, Sendable, Hashable {
        let type: ServerEnum<ReactionType>
        let count: Int
    }

    let total: Int
    let counts: [Count]
    /// 요청자가 남긴 반응. 없으면 null.
    let mine: ServerEnum<ReactionType>?
}

/* 서버가 보는 포스트. 0.1.0의 `ComposedPost`(로컬 레코드)를 대체한다.
 *
 * `template`이 **포스트 안에 박혀 있다** — 렌더할 때 `GET /templates`를 다시 부를 필요가 없고,
 * 템플릿이 나중에 바뀌어도 이미 발행된 포스트는 찍힌 배치를 유지한다.
 *
 * 0.2.0에서 쓰지 않는 필드도 지우지 않고 받는다(`commentCount`·`reactions`) — 받아 두는
 * 비용은 0이고, 빼 두면 그 화면을 만드는 브랜치가 이 파일을 다시 열어야 한다. */
struct Post: Decodable, Sendable, Hashable {
    let id: UUID
    let author: PostAuthor
    let template: Template
    /* **null일 수 있다.** 서버가 null을 기본 프레임으로 풀어 주지 않으므로
     * (`postsService.ts`가 `frame === null ? null : …`) `frameId`를 넣지 않은 draft는
     * 여기가 비어 온다. 렌더하는 쪽이 기본값을 정해야 한다. */
    let frame: Frame?
    let status: ServerEnum<PostStatus>
    let visibility: ServerEnum<PostVisibility>
    let caption: String?
    /// 명세 §6.3 대표 컷. 0.1.0에서 소비처가 없어 미구현이었는데 서버에 필드가 있다.
    let thumbnailCutIndex: Int?
    let cuts: [PostCut]
    /// **iOS가 만든 합성본.** draft에는 없으므로 null이다 — required이면서 nullable이다.
    let composed: Media?
    let publishedAt: String?
    let createdAt: String
    let commentCount: Int
    let reactions: ReactionSummary
    /// 요청자 기준 보관 여부. 0.1.0의 로컬 `archive.json`을 대체한다.
    let bookmarked: Bool
}

/// 커서 페이지. 서버 `pageSchema`가 모든 목록에 같은 모양을 씌운다.
struct Page<Item: Decodable & Sendable>: Decodable, Sendable {
    let items: [Item]
    /// null이면 마지막 페이지다.
    let nextCursor: String?
}

typealias PostPage = Page<Post>

struct CreatePostBody: Encodable, Sendable {
    let templateId: UUID
}

struct PatchPostBody: Encodable, Sendable {
    struct CutInput: Encodable, Sendable {
        let cutIndex: Int
        let mediaId: UUID
    }

    /* 전부 optional이다 — **보낸 키만** 반영된다. 그래서 `caption`을 지우는 것과
     * 건드리지 않는 것을 구별해야 한다: 전자는 `null`을 실어야 하고 후자는 키를 빼야 한다.
     * `String?`으로는 둘이 같은 표현이 되어 캡션을 지울 수단이 없어진다. */
    var templateId: UUID?
    /// `.null`을 보내면 프레임을 지운다 — 그 포스트의 `frame`이 null로 내려온다.
    var frameId: Field<UUID>?
    var caption: Field<String>?
    var visibility: ServerEnum<PostVisibility>?
    var thumbnailCutIndex: Field<Int>?
    var cuts: [CutInput]?
}

struct PublishPostBody: Encodable, Sendable {
    let composedMediaId: UUID
    var caption: Field<String>?
    var visibility: ServerEnum<PostVisibility>?
    var thumbnailCutIndex: Int?
}

/* 보관 토글 응답. `PUT`은 `true`, `DELETE`는 `false`를 돌려준다 —
 * 멱등이라 두 번 눌러도 같은 값이다(서버가 유니크 인덱스로 보장한다). */
struct BookmarkResult: Decodable, Sendable {
    let bookmarked: Bool
}

/* 이름에 `Response`가 붙은 이유: `ShareLink`는 SwiftUI의 공유 버튼 타입이다.
 * 0.1.0의 포스트 상세·친구 탭이 그것을 쓰고 있어서 같은 이름을 쓰면 그 화면들이 깨진다. */
struct ShareLinkResponse: Decodable, Sendable {
    let url: String
}

// MARK: - optional × nullable

/* "키를 빼기"와 "null을 싣기"를 나누는 표현. 서버가 PATCH를 **보낸 키만** 반영하므로
 * 이 구분이 실제 동작을 가른다 — 캡션을 지우려면 `null`이 가야 하고, 건드리지 않으려면
 * 키가 없어야 한다.
 *
 * `Optional<Optional<T>>`로도 되지만 호출부가 `.some(nil)`을 읽어야 해서 뜻이 드러나지 않는다.
 * `Encodable`만 채택한다 — 응답에서는 이 구분이 필요 없다(서버가 항상 키를 준다). */
enum Field<Value: Encodable & Sendable>: Encodable, Sendable {
    case value(Value)
    /// 서버에 `null`을 실어 값을 지운다.
    case null

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .value(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}
