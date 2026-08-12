/* 합성 결과 로컬 저장 — 백엔드가 아직 없으므로 Documents에 JPEG + JSON 인덱스로 둔다.
 * 스파이크 범위상 HTTP 계층은 만들지 않는다. */

import Observation
import UIKit

@MainActor
@Observable
final class FeedStore {
    private(set) var posts: [ComposedPost] = []

    private let fileManager = FileManager.default

    private var documents: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var postsDirectory: URL {
        documents.appendingPathComponent("Posts", isDirectory: true)
    }

    private var indexURL: URL {
        documents.appendingPathComponent("posts.json")
    }

    init() {
        try? fileManager.createDirectory(at: postsDirectory, withIntermediateDirectories: true)
        load()
    }

    func imageURL(for post: ComposedPost) -> URL {
        postsDirectory.appendingPathComponent(post.imageFilename)
    }

    func image(for post: ComposedPost) -> UIImage? {
        UIImage(contentsOfFile: imageURL(for: post).path)
    }

    /// 합성 결과를 저장하고 피드 맨 앞에 붙인다.
    @discardableResult
    func save(
        image: UIImage,
        count: CutCount,
        layout: CutLayout,
        frameID: String?,
        filterID: FilterID,
        caption: String
    ) -> ComposedPost? {
        let id = UUID()
        let filename = "\(id.uuidString).jpg"
        guard let data = image.jpegData(compressionQuality: 0.92) else { return nil }

        do {
            try data.write(to: postsDirectory.appendingPathComponent(filename), options: .atomic)
        } catch {
            return nil
        }

        let post = ComposedPost(
            id: id,
            createdAt: Date(),
            imageFilename: filename,
            count: count,
            layout: layout,
            frameID: frameID,
            filterID: filterID,
            caption: caption
        )
        posts.insert(post, at: 0)
        persist()
        return post
    }

    func delete(_ post: ComposedPost) {
        try? fileManager.removeItem(at: imageURL(for: post))
        posts.removeAll { $0.id == post.id }
        persist()
    }

    // MARK: - 영속화

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        posts = (try? decoder.decode([ComposedPost].self, from: data)) ?? []
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(posts) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}
