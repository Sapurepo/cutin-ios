/* API 기준 주소.
 *
 * 코드에 박지 않고 **빌드 구성에서** 온다 — Debug는 로컬 서버, Release는 운영 서버를 봐야 하고
 * 그 값이 소스에 있으면 구성마다 코드가 갈린다. 0.1.0에서 xcconfig를 분리해 둔 이유가 이것이다.
 *
 *     Config/Shared.xcconfig   CUTIN_SLASH = /
 *     Config/Debug.xcconfig    CUTIN_API_BASE_URL = http:$(CUTIN_SLASH)$(CUTIN_SLASH)localhost:8000
 *     Config/Info.plist        CutinAPIBaseURL = $(CUTIN_API_BASE_URL)
 *
 * **슬래시를 변수로 넣는 것은 우회가 아니라 필수다.** xcconfig에서 `//`는 주석 시작이고
 * 주석 제거가 변수 확장보다 먼저 일어난다 — `http://호스트`는 `http:`로 잘리고,
 * 흔히 인용되는 `http:$()//호스트`도 같이 잘린다(빌드된 Info.plist에서 확인했다).
 * 리터럴 `//`가 나타나지 않아야 살아남는다. */

import Foundation

enum APIConfig {
    private static let plistKey = "CutinAPIBaseURL"

    /* 값이 없거나 URL이 아니면 **첫 호출에서 크래시한다.** 조용히 폴백하지 않는 이유는
     * 폴백 주소로 붙으면 "왜 내 서버에 요청이 안 오는지"를 네트워크 로그로 쫓게 되기 때문이다.
     * Release 구성은 운영 주소를 채우기 전까지 이 지점에서 멈춘다 — 의도한 것이다. */
    static let baseURL: URL = {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: plistKey) as? String,
              !raw.isEmpty
        else {
            preconditionFailure(
                "\(plistKey)가 비어 있습니다. Config/*.xcconfig의 CUTIN_API_BASE_URL을 채우세요."
            )
        }
        guard let url = URL(string: raw), url.scheme != nil, url.host != nil else {
            preconditionFailure(
                "\(plistKey)가 URL이 아닙니다: \"\(raw)\". "
                    + "xcconfig에서 `//`가 주석으로 먹혔을 수 있습니다 — `http:$()//호스트` 형태로 쓰세요."
            )
        }
        return url
    }()
}
