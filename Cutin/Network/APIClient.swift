/* HTTP 전송. 계약 타입(`Contracts.swift`)을 실어 보내고 받아온다.
 *
 * **엔드포인트별 메서드를 만들지 않는다.** `send`가 둘(응답 있음/없음)뿐이고 경로는 호출부가
 * 문자열로 넘긴다. 40여 엔드포인트마다 래퍼를 만들면 그 래퍼가 계약 문서의 사본이 되어
 * 스펙이 바뀔 때 두 곳을 고쳐야 한다. 경로를 아는 것은 그 기능을 만드는 계층의 일이다.
 *
 * `actor`인 이유는 액세스 토큰이 가변 상태이기 때문이다. 요청은 여러 화면에서 동시에 나가고
 * 토큰은 재발급으로 바뀐다 — `@MainActor`로 두면 네트워크 대기가 메인 액터를 잡는다.
 *
 * 401을 만나면 **한 번** 재발급하고 같은 요청을 재시도한다. 재발급 자체는 여기서 하지 않고
 * `refresher`로 주입받는다 — 리프레시 토큰을 Keychain에 넣고 꺼내는 일은 세션의 몫이고,
 * 전송 계층이 보관소를 알면 둘이 서로를 알게 된다. */

import Foundation

actor APIClient {
    enum Method: String {
        case get = "GET"
        case post = "POST"
        case patch = "PATCH"
        case put = "PUT"
        case delete = "DELETE"
    }

    private let baseURL: URL
    private let session: URLSession
    private var accessToken: String?

    /* 401을 받았을 때 새 액세스 토큰을 얻어 오는 일. 세션이 심는다.
     * nil이면 재발급을 시도하지 않고 401을 그대로 올린다 — 로그인 전 상태다. */
    private var refresher: (@Sendable () async throws -> String)?

    /* 진행 중인 재발급. 동시에 401을 맞은 요청들이 각자 재발급을 부르면 리프레시 토큰이
     * 여러 번 쓰이고, 서버가 회전(rotation)을 한다면 뒤늦은 것들이 폐기된 토큰으로 실패한다.
     * 첫 요청이 만든 작업을 나머지가 기다린다. */
    private var refreshTask: Task<String, any Error>?

    init(baseURL: URL = APIConfig.baseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func setAccessToken(_ token: String?) {
        accessToken = token
    }

    func setRefresher(_ refresher: (@Sendable () async throws -> String)?) {
        self.refresher = refresher
    }

    // MARK: - 보내기

    /// 응답 본문을 디코드해 돌려준다.
    func send<Response: Decodable & Sendable>(
        _ method: Method,
        _ path: String,
        query: [String: String] = [:],
        body: (any Encodable & Sendable)? = nil,
        authorized: Bool = true,
        as type: Response.Type = Response.self
    ) async throws -> Response {
        let data = try await perform(method, path, query: query, body: body, authorized: authorized)
        do {
            return try Self.decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    /// 본문을 쓰지 않는 요청(로그아웃·삭제 등). 2xx면 성공이다.
    func send(
        _ method: Method,
        _ path: String,
        query: [String: String] = [:],
        body: (any Encodable & Sendable)? = nil,
        authorized: Bool = true
    ) async throws {
        _ = try await perform(method, path, query: query, body: body, authorized: authorized)
    }

    /* 바이트를 그대로 올린다. `send`를 쓸 수 없는 이유가 둘이다:
     *
     * ① **본문이 JSON이 아니다.** 이미지 바이트를 그대로 싣고 Content-Type도 서버가 지정한다.
     * ② **목적지가 서버가 준 URL이다.** 지금은 서버 자신의 `/media/content/...`지만 스토리지
     *    벤더가 확정되면 외부 절대 URL이 될 수 있어, 경로를 앱이 조립하지 않는다.
     *
     * 그래도 401 → 재발급 → 재시도는 똑같이 탄다. `PUT /media/content/{path}`가 `[auth]`이고,
     * 컷을 여러 장 올리는 동안 토큰이 만료되는 것은 흔한 일이다. */
    func upload(_ data: Data, to target: UploadTarget) async throws {
        let url = try url(forTarget: target.url)
        _ = try await perform(authorized: true) {
            var request = URLRequest(url: url)
            request.httpMethod = target.method
            request.httpBody = data
            // 서버가 준 헤더를 그대로 싣는다 — Content-Type이 여기 온다.
            for (key, value) in target.headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
            return request
        }
    }

    // MARK: - 내부

    private func perform(
        _ method: Method,
        _ path: String,
        query: [String: String],
        body: (any Encodable & Sendable)?,
        authorized: Bool
    ) async throws -> Data {
        let url = try url(for: path, query: query)
        return try await perform(authorized: authorized) {
            var request = URLRequest(url: url)
            request.httpMethod = method.rawValue
            if let body {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                do {
                    request.httpBody = try Self.encoder.encode(body)
                } catch {
                    // 계약 타입이 인코딩에 실패하는 것은 코드 결함이다 — 서버 탓이 아니다.
                    throw APIError.decoding(error)
                }
            }
            return request
        }
    }

    /* 401이면 재발급 후 **한 번만** 재시도한다. 재발급이 성공했는데도 다시 401이 오는 경우
     * (권한이 아예 없는 리소스, 서버 버그)에 요청이 끝없이 오가는 것을 막는다.
     *
     * 완성된 요청이 아니라 요청을 **만드는 법**을 받는다. JSON 요청과 바이트 업로드가 같은 401
     * 처리를 타야 하는데, 완성된 `URLRequest`를 받으면 재시도할 때 인증 헤더가 옛 토큰인 채로
     * 남는다(헤더는 `attempt`가 붙인다). */
    private func perform(
        authorized: Bool,
        _ build: @Sendable () throws -> URLRequest
    ) async throws -> Data {
        do {
            return try await attempt(authorized: authorized, build)
        } catch let error as APIError where error.isUnauthorized && authorized && refresher != nil {
            accessToken = try await refreshedToken()
            return try await attempt(authorized: authorized, build)
        }
    }

    /// 진행 중인 재발급이 있으면 그것을 기다린다.
    private func refreshedToken() async throws -> String {
        if let refreshTask {
            return try await refreshTask.value
        }
        guard let refresher else {
            throw APIError.server(
                status: 401, code: APIError.Code.unauthorized.rawValue,
                message: "로그인이 필요합니다.", details: nil
            )
        }
        let task = Task { try await refresher() }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private func attempt(
        authorized: Bool,
        _ build: @Sendable () throws -> URLRequest
    ) async throws -> Data {
        var request = try build()

        /* 인증이 필요한데 토큰이 없으면 **요청을 보내지 않는다.** 보내면 서버가 401을 주고
         * 재발급 경로를 타는데, 애초에 토큰이 없으므로 재발급도 실패한다. 상태를 정직하게
         * 401로 만들어 로그인 화면으로 보내는 것이 짧다. */
        if authorized {
            guard let accessToken else {
                throw APIError.server(
                    status: 401, code: APIError.Code.unauthorized.rawValue,
                    message: "로그인이 필요합니다.", details: nil
                )
            }
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.malformedResponse(status: -1, snippet: Self.snippet(data))
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.failure(status: http.statusCode, data: data)
        }
        return data
    }

    private func url(for path: String, query: [String: String]) throws -> URL {
        /* `appendingPathComponent`가 아니라 상대 URL 해석을 쓴다 — 기준 주소에 경로가
         * 붙어 있는 경우(리버스 프록시 뒤의 `/api`)에도 맞물린다. */
        guard let base = URL(string: path.hasPrefix("/") ? String(path.dropFirst()) : path,
                             relativeTo: baseURL),
              var components = URLComponents(url: base, resolvingAgainstBaseURL: true)
        else {
            throw APIError.malformedResponse(status: -1, snippet: "잘못된 경로: \(path)")
        }
        if !query.isEmpty {
            // 키 순서를 고정한다 — 로그와 캐시 키가 호출마다 달라지지 않게.
            components.queryItems = query.sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else {
            throw APIError.malformedResponse(status: -1, snippet: "잘못된 쿼리: \(query)")
        }
        return url
    }

    /* 업로드 목적지. 서버가 절대 URL(`http://…/media/content/…`)을 주지만, 스토리지 벤더가
     * 바뀌거나 리버스 프록시 뒤에 놓이면 상대 경로가 올 수도 있다. 둘 다 받는다 —
     * `URL(string:relativeTo:)`은 문자열에 스킴이 있으면 기준 주소를 무시한다. */
    private func url(forTarget target: String) throws -> URL {
        guard let url = URL(string: target, relativeTo: baseURL) else {
            throw APIError.malformedResponse(status: -1, snippet: "잘못된 업로드 주소: \(target)")
        }
        return url
    }

    /// 2xx가 아닌 응답을 오류로 바꾼다. 오류 봉투가 아니면 `malformedResponse`다.
    private static func failure(status: Int, data: Data) -> APIError {
        guard let envelope = try? decoder.decode(APIErrorEnvelope.self, from: data) else {
            return .malformedResponse(status: status, snippet: snippet(data))
        }
        return .server(
            status: status,
            code: envelope.error.code,
            message: envelope.error.message,
            // `details`는 모양이 정해지지 않은 값(`z.unknown()`)이라 원본 바이트로 보관한다.
            details: data
        )
    }

    /// 로그에 실을 만큼만 자른다 — HTML 오류 페이지가 통째로 올라오는 것을 막는다.
    private static func snippet(_ data: Data) -> String {
        let text = String(decoding: data.prefix(300), as: UTF8.self)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /* 키 변환을 걸지 않는다. 서버가 이미 camelCase로 내려보내고(`nestjs-zod`가 Zod 키를
     * 그대로 쓴다) 변환을 걸면 `avatarUrl` → `avatar_url`처럼 없는 키를 찾게 된다. */
    private static let decoder = JSONDecoder()
    private static let encoder = JSONEncoder()
}
