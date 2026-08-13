/* 서버 오류 표현.
 *
 * 서버는 상태 코드와 무관하게 **한 가지 모양**으로만 오류를 낸다
 * (`appExceptionFilter.ts`): `{ "error": { "code", "message", "details"? } }`.
 * `code`가 분기용 안정 식별자이고 `message`는 사람이 읽는 한국어 문장이다.
 *
 * **사용자 표시 문구를 여기서 만들지 않는다.** 0.1.0에 오류 배너가 없어서(소비처가 없어
 * 만들지 않았다) 지금 문구를 지어 두면 아무도 읽지 않는 상수 표가 된다. 서버가 이미
 * 한국어 `message`를 주므로 배너를 만드는 브랜치가 그것을 쓸지 자기 문구를 쓸지 정하면 된다. */

import Foundation

enum APIError: Error {
    /// 요청이 서버에 닿지 못했다 — 오프라인·타임아웃·DNS. 재시도가 의미 있는 유일한 경우다.
    case transport(any Error)

    /// 서버가 계약대로 낸 오류.
    case server(status: Int, code: String, message: String, details: Data?)

    /* 2xx가 아닌데 오류 봉투도 아니다 — 프록시가 낸 HTML, 게이트웨이 타임아웃, 계약 변경.
     * `server`와 섞으면 "code로 분기"가 빈 문자열에 걸려 조용히 잘못된 분기를 탄다. */
    case malformedResponse(status: Int, snippet: String)

    /// 2xx인데 본문이 계약과 다르다. 계약 위반이므로 재시도해도 같다.
    case decoding(any Error)

    /// 서버가 쓰는 코드 전수(`grep "code: '...'"` — 열거형 값은 제외).
    enum Code: String {
        case validationFailed = "VALIDATION_FAILED"
        case unauthorized = "UNAUTHORIZED"
        case forbidden = "FORBIDDEN"
        case notFound = "NOT_FOUND"
        case conflict = "CONFLICT"
        case payloadTooLarge = "PAYLOAD_TOO_LARGE"
        case unsupportedMediaType = "UNSUPPORTED_MEDIA_TYPE"
        case internalError = "INTERNAL_ERROR"
    }

    /// 모르는 코드는 nil이다 — 서버가 코드를 추가해도 `switch`가 깨지지 않는다.
    var code: Code? {
        guard case .server(_, let code, _, _) = self else { return nil }
        return Code(rawValue: code)
    }

    /* 토큰 재발급이 필요한 상태. 상태 코드만 보면 안 되는 이유는 `FORBIDDEN`(403)도
     * 인증 실패처럼 보이지만 재발급으로 풀리지 않기 때문이다 — 권한이 없는 것이다. */
    var isUnauthorized: Bool {
        if case .server(let status, _, _, _) = self { return status == 401 }
        return false
    }
}

/// 오류 봉투. 디코드 자체가 실패하면 `malformedResponse`로 떨어진다.
struct APIErrorEnvelope: Decodable {
    struct Payload: Decodable {
        let code: String
        let message: String
    }

    let error: Payload
}
