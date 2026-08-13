/* 임시 검증 하니스 — 커밋 전에 삭제한다.
 *
 * 두 방향을 본다:
 *   ① 응답: openapi.json에서 **생성한** 페이로드가 계약 타입으로 디코드되는가
 *      (`ContractFixtures.generated.swift` — 손으로 쓰면 내 가정을 시험하게 된다)
 *   ② 요청: 계약 타입을 인코딩한 JSON을 찍어 파이썬이 스펙 스키마와 대조한다
 *
 * 실행: SIMCTL_CHILD_CONTRACT_CHECK=1 로 앱을 띄우면 stdout에 결과를 뱉고 끝낸다. */

#if DEBUG
import Foundation

enum ContractHarness {
    static var isRequested: Bool {
        ProcessInfo.processInfo.environment["CONTRACT_CHECK"] == "1"
    }

    static func run() {
        var failures = 0
        print("=== ① 응답 디코드 (스펙 생성 페이로드) ===")
        for testCase in ContractFixtures.all {
            let data = Data(testCase.json.utf8)
            do {
                try testCase.decode(data)
                print("PASS  \(testCase.name)")
            } catch {
                failures += 1
                print("FAIL  \(testCase.name)  \(error)")
            }
        }

        /* 스펙에서 생성할 수 없는 케이스 — **스펙에 없는 열거형 값**. 서버가 값을 추가한
         * 미래를 흉내낸다. 던지면 피드 한 페이지가 통째로 사라진다는 주장의 증명. */
        print("=== ①-b 모르는 열거형 값 (스펙 밖 · 손으로 만든 유일한 케이스) ===")
        let future = ContractFixtures.all.first { $0.name == "Post/full" }!.json
            .replacingOccurrences(of: "\"status\": \"draft\"", with: "\"status\": \"archived\"")
            .replacingOccurrences(of: "\"mine\": \"like\"", with: "\"mine\": \"angry\"")
        do {
            let post = try JSONDecoder().decode(Post.self, from: Data(future.utf8))
            let passed = post.status.raw == "archived" && post.status.known == nil
                && post.reactions.mine?.raw == "angry" && post.reactions.mine?.known == nil
            if passed {
                print("PASS  모르는 값을 원시 문자열로 통과시킴 (known == nil)")
            } else {
                failures += 1
                print("FAIL  원시값 보존 실패: status=\(post.status.raw)")
            }
        } catch {
            failures += 1
            print("FAIL  모르는 열거형에서 던졌다 — 서버가 값을 추가하면 화면이 빈다: \(error)")
        }

        print("=== ② 요청 인코드 (파이썬이 스펙과 대조) ===")
        emit("OauthLoginBodyDto", OAuthLoginBody(token: "tok"))
        emit("RefreshBodyDto", RefreshBody(refreshToken: "tok"))
        emit("UpdateMeBodyDto", UpdateMeBody(nickname: "네컷러버", timezone: "Asia/Seoul",
                                            avatarMediaId: .value(sampleID)))
        emit("UpdateMeBodyDto", UpdateMeBody(avatarMediaId: .null))
        emit("CreateUploadBodyDto", CreateUploadBody(kind: ServerEnum(.cut), mime: ServerEnum(.jpeg)))
        emit("CompleteUploadBodyDto", CompleteUploadBody(width: 1080, height: 1440))
        emit("CreatePostBodyDto", CreatePostBody(templateId: sampleID))
        emit("UpdatePostBodyDto", PatchPostBody(
            templateId: sampleID, caption: .value("첫 컷인"), visibility: ServerEnum(.friends),
            thumbnailCutIndex: .value(2),
            cuts: [.init(cutIndex: 0, mediaId: sampleID), .init(cutIndex: 1, mediaId: sampleID)]
        ))
        // 프레임을 지정하는 요청
        emit("UpdatePostBodyDto", PatchPostBody(frameId: .value(sampleID)))
        // 캡션·대표 컷·프레임을 **지우는** 요청 — null이 실려야 하고 키가 빠지면 안 된다
        emit("UpdatePostBodyDto", PatchPostBody(frameId: .null, caption: .null, thumbnailCutIndex: .null))
        // 아무것도 안 건드리는 요청 — 키가 하나도 없어야 한다
        emit("UpdatePostBodyDto", PatchPostBody())
        emit("PublishPostBodyDto", PublishPostBody(composedMediaId: sampleID,
                                                  caption: .value("캡션"),
                                                  visibility: ServerEnum(.public),
                                                  thumbnailCutIndex: 0))
        emit("PublishPostBodyDto", PublishPostBody(composedMediaId: sampleID))

        print("=== 결과: \(failures == 0 ? "디코드 전부 통과" : "디코드 실패 \(failures)건") ===")
        fflush(stdout)
        exit(failures == 0 ? 0 : 1)
    }

    private static let sampleID = UUID(uuidString: "3f2c1b4a-5d6e-4f70-8a9b-0c1d2e3f4a5b")!

    private static func emit(_ specName: String, _ value: some Encodable) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value),
              let text = String(data: data, encoding: .utf8)
        else {
            print("ENCFAIL \(specName)")
            return
        }
        print("ENC \(specName) \(text)")
    }
}

/// 생성 파일이 부르는 디코드 어댑터.
func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws {
    _ = try JSONDecoder().decode(type, from: data)
}
#endif
