/* 진행 중인 촬영의 영속 — 명세 §5.3.
 *
 * 컷을 **촬영 즉시** 파일로 내린다. 메모리의 `[UIImage]`는 앱이 죽으면 사라지고, iOS는
 * 백그라운드 앱을 쉽게 정리한다 — 4컷 중 3컷을 찍고 다른 앱을 잠깐 보고 오면 사진이 없어진다.
 * 이탈 시점에 몰아 쓰는 방식으로는 그 경우를 막을 수 없다(이탈 훅이 불리지 않는다).
 *
 * draft는 1개로 제한되므로(§5.3 확정) 계획의 `Drafts/<uuid>/` 하위 디렉터리를 두지 않았다.
 * 디렉터리 하나로 충분하고, 폐기가 "이 디렉터리 비우기"로 끝난다.
 *
 *     Documents/Drafts/{draft.json, cut-0.jpg, cut-1.jpg, …}
 *
 * `Capture/`가 아니라 `Storage/`에 둔 이유: FileVault·PostFileStore를 그대로 감싸는 저장 계층이라
 * 나머지 store들과 같은 자리에 있어야 파일 규칙을 한눈에 볼 수 있다. */

import UIKit

struct DraftStore: Sendable {
    /// 파일로 남는 draft 메타. 컷 자체는 JPEG로 따로 있다.
    struct Draft: Codable, Sendable {
        /// 첫 컷을 찍은 시각. 24h 만료의 기준이다.
        var createdAt: Date
        var count: CutCount
        var mode: CaptureMode
        /// 실제로 찍힌 컷 수. 읽을 때 파일 수와 맞춰 줄인다.
        var cutCount: Int
        var templateID: String
        var filterID: FilterID
        var caption: String
    }

    /// 24h(§5.3 확정). 만료는 **읽는 시점**에 판정한다 — 로컬 전용 단계에서는 앱이 꺼져 있는 동안
    /// 돌 스케줄러가 없으므로 "백그라운드에서 지운다"는 정책이 성립하지 않는다.
    static let lifetime: TimeInterval = 24 * 60 * 60

    private static let metaName = "draft.json"

    private let vault: FileVault
    private let files: PostFileStore

    init() {
        let vault = FileVault(directory: "Drafts")
        self.vault = vault
        self.files = PostFileStore(vault: vault)
    }

    private func cutName(_ index: Int) -> String { "cut-\(index).jpg" }

    // MARK: - 읽기

    /* 만료·부분 쓰기를 여기서 걸러낸다. 컷 쓰기는 셔터를 막지 않으려고 떼어 보내므로
     * (`CaptureFlow.persist`) 메타에 적힌 수보다 파일이 적을 수 있다 — 그때 4컷을 약속하고
     * 3장을 내주면 복구된 촬영이 빈 슬롯을 갖게 된다. 파일 수가 진실이다. */
    func load() -> Draft? {
        guard vault.exists(Self.metaName),
              let data = try? vault.read(Self.metaName),
              var draft = try? FileVault.decoder().decode(Draft.self, from: data)
        else { return nil }

        if Date().timeIntervalSince(draft.createdAt) > Self.lifetime {
            clear()
            return nil
        }

        let present = (0..<draft.cutCount).prefix { belongs($0, to: draft) }.count
        guard present > 0 else {
            clear()
            return nil
        }
        draft.cutCount = present
        return draft
    }

    /* 이 draft의 컷인가. 존재만 보면 **이전 촬영의 잔여 파일**을 셀 수 있다: 컷 쓰기는 셔터를
     * 막지 않으려고 떼어 보내므로 `clear()` 뒤에 늦게 착지할 수 있고, 그러면 유효한 인덱스에
     * 남의 사진이 놓인다. 생성 시각이 이 draft보다 앞서면 이 촬영의 것이 아니다.
     * (원자적 쓰기는 임시 파일을 rename하므로 덮어쓴 파일도 생성 시각이 새로 잡힌다.) */
    private func belongs(_ index: Int, to draft: Draft) -> Bool {
        guard let created = vault.creationDate(cutName(index)) else { return false }
        // 메타를 먼저 쓰고 파일이 뒤따르는 순서라 약간의 여유를 둔다.
        return created >= draft.createdAt.addingTimeInterval(-2)
    }

    /// 원본 해상도로 되살린다. 합성이 셀 크기로 다시 줄이므로 상한만 걸어 둔다.
    /// nonisolated이라 호출부가 메인 액터 밖으로 옮겨 실행할 수 있다 — 12MP 디코드 여러 장이다.
    ///
    /// 디코드가 깨지면 **거기서 멈춘다.** `compactMap`으로 건너뛰면 뒤 컷이 앞으로 당겨져
    /// 파일 인덱스와 메모리 슬롯이 어긋나고, 다음 촬영이 그 자리를 덮어써 같은 사진이 두 번
    /// 들어간다. `load()`가 파일을 세는 규칙과 같아야 한다.
    func loadCuts(_ count: Int) -> [UIImage] {
        var loaded: [UIImage] = []
        for index in 0..<count {
            guard let image = files.decode(cutName(index), maxPixel: 4096) else { break }
            loaded.append(image)
        }
        return loaded
    }

    func thumbnail(maxPixel: CGFloat) -> UIImage? {
        files.decode(cutName(0), maxPixel: maxPixel)
    }

    // MARK: - 쓰기

    func save(_ draft: Draft) throws {
        try vault.write(FileVault.encoder().encode(draft), to: Self.metaName)
    }

    func writeCut(_ image: UIImage, at index: Int) throws {
        try files.write(image, to: cutName(index))
    }

    /// 디렉터리 안을 비운다. 디렉터리 자체는 남긴다 — FileVault가 만들어 두는 것이라 지우면
    /// 다음 쓰기가 없는 경로를 향한다.
    func clear() {
        try? vault.remove(Self.metaName)
        for name in (try? vault.names(withExtension: "jpg")) ?? [] {
            try? vault.remove(name)
        }
    }
}
