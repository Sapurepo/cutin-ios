/* Documents 하위 한 디렉터리에 대한 파일 접근 규칙 — 디렉터리 보장 · 원자적 쓰기 ·
 * JSON 코덱 설정을 한곳에 모은다.
 *
 * 포스트 인덱스(JSON)와 합성 이미지(JPEG)가 같은 규칙을 쓰고, draft 저장(§5.3)도 이걸 재사용한다.
 * 원자적 쓰기가 기본값인 이유: 쓰다가 죽으면 반쯤 쓰인 파일이 남고, 그게 인덱스 JSON이면
 * 다음 실행에서 디코드가 깨진다. */

import Foundation

struct FileVault: Sendable {
    let root: URL

    private init(root: URL) {
        self.root = root
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// Documents 자체 — 기존 설치의 `posts.json`이 여기 있어 경로를 옮기지 않는다.
    static func documents() -> FileVault {
        FileVault(root: documentsURL)
    }

    /// Documents 하위 디렉터리
    init(directory: String) {
        self.init(root: Self.documentsURL.appending(path: directory, directoryHint: .isDirectory))
    }

    private static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    func url(_ name: String) -> URL {
        root.appending(path: name, directoryHint: .notDirectory)
    }

    func write(_ data: Data, to name: String) throws {
        try data.write(to: url(name), options: .atomic)
    }

    func read(_ name: String) throws -> Data {
        try Data(contentsOf: url(name))
    }

    func remove(_ name: String) throws {
        try FileManager.default.removeItem(at: url(name))
    }

    func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: url(name).path)
    }

    func names(withExtension ext: String) throws -> [String] {
        try FileManager.default
            .contentsOfDirectory(atPath: root.path)
            .filter { $0.hasSuffix(".\(ext)") }
    }

    /// 망가진 파일을 지우지 않고 옆으로 치운다 — 사용자 데이터를 버리지 않으려면 덮어쓰기 대신 이동.
    /// 이름이 이미 있으면 그것도 남겨야 하므로 번호를 붙인다.
    func moveAside(_ name: String, suffix: String) throws -> URL {
        var destination = url("\(name).\(suffix)")
        var attempt = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = url("\(name).\(suffix)-\(attempt)")
            attempt += 1
        }
        try FileManager.default.moveItem(at: url(name), to: destination)
        return destination
    }

    /// 파일 생성 시각 — 인덱스를 잃었을 때 촬영 순서를 되살리는 유일한 단서.
    func creationDate(_ name: String) -> Date? {
        try? FileManager.default
            .attributesOfItem(atPath: url(name).path)[.creationDate] as? Date
    }

    // MARK: - JSON

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
