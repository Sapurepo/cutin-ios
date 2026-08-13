/* 포스트 상세 — 명세 §7. 원본 `apps/mobile/src/app/post/[id].tsx` 대응.
 *
 * 담은 것: §7.1 공유, §7.4 보관, §7.5 삭제, 그리고 사진 앱 저장
 * (`Info.plist`의 `NSPhotoLibraryAddUsageDescription`이 이미 약속한 기능이다).
 *
 * 담지 않은 것: §7.2 댓글 · §7.3 반응. 내 포스트에 내 반응은 의미가 없고, 0.2.0에서 서버가
 * 소유하는 상태로 즉시 대체된다. 빈 댓글창은 "곧 됩니다"가 아니라 "고장났다"로 읽힌다.
 *
 * 포스트를 값으로 받지 않고 id로 되찾는다(규칙 4) — 목록에서 삭제·보관이 바뀌면 여기도 따라야 한다. */

import Photos
import SwiftUI

struct PostDetailView: View {
    let id: UUID

    @Environment(FeedStore.self) private var store
    @Environment(ArchiveStore.self) private var archive
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var notice: String?
    @State private var isSavingToPhotos = false

    var body: some View {
        Group {
            if let post = store.post(id: id) {
                content(post)
            } else {
                // 다른 경로에서 지워졌다. 빈 화면보다 이유를 말하는 게 낫다.
                EmptyStateView(
                    title: "삭제된 포스트예요",
                    message: "목록에서 이미 지워졌어요",
                    systemImage: "trash"
                )
            }
        }
        .background(palette.bg)
        .navigationTitle("포스트")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ post: ComposedPost) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.x4) {
                PostImage(post: post)

                meta(post)
                if !post.caption.isEmpty {
                    Text(post.caption)
                        .font(Typography.bodyText)
                        .foregroundStyle(palette.textPrimary)
                }
                if post.recoveredFromFile == true { recoveredNotice }
                if let notice { noticeLabel(notice) }

                actions(post)
            }
            .padding(Spacing.x4)
        }
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button("삭제", role: .destructive) { delete(post) }
            }
        }
    }

    // MARK: - 본문

    private func meta(_ post: ComposedPost) -> some View {
        HStack(spacing: Spacing.x2) {
            Text(post.createdAt, format: .dateTime.year().month().day().hour().minute())
                .font(Typography.numeric)
                .foregroundStyle(palette.textSecondary)
            if post.filterID != .original {
                Text(post.filterID.displayName)
                    .font(Typography.chip)
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, Spacing.x2)
                    .padding(.vertical, 2)
                    .tokenBorder(Capsule(), color: palette.border)
            }
        }
    }

    /// 인덱스를 잃고 사진에서 되살린 레코드는 컷 수·레이아웃·보정이 자리값이다.
    /// 화면에 그 값을 진짜처럼 보여주면 안 된다.
    private var recoveredNotice: some View {
        Text("목록을 복구한 포스트라 캡션과 보정 정보가 없어요")
            .font(Typography.caption)
            .foregroundStyle(palette.textSecondary)
    }

    private func noticeLabel(_ message: String) -> some View {
        Text(message)
            .font(Typography.caption)
            .foregroundStyle(palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actions(_ post: ComposedPost) -> some View {
        HStack(spacing: Spacing.x2) {
            /* 파일 URL을 넘긴다 — `Image`를 넘기면 SwiftUI가 다시 인코딩해 화질이 한 번 더 깎인다.
             * 서버 없이 완전히 동작하는 기능이라 0.1.0에 그대로 남는다. */
            ShareLink(item: store.imageURL(for: post)) {
                actionLabel("공유", systemImage: "square.and.arrow.up")
            }

            Button {
                Task { await saveToPhotos(post) }
            } label: {
                actionLabel(isSavingToPhotos ? "저장 중…" : "사진 앱에 저장",
                            systemImage: "arrow.down.to.line")
            }
            .disabled(isSavingToPhotos)

            Button {
                archive.toggle(post.id)
            } label: {
                let saved = archive.contains(post.id)
                actionLabel(saved ? "보관 해제" : "보관",
                            systemImage: saved ? "bookmark.fill" : "bookmark")
            }
        }
        .buttonStyle(.glass)
        .frame(maxWidth: .infinity)
    }

    private func actionLabel(_ title: String, systemImage: String) -> some View {
        VStack(spacing: Spacing.x1) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
            Text(title)
                .font(Typography.chip)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.x2)
    }

    // MARK: - 동작

    private func delete(_ post: ComposedPost) {
        guard (try? store.delete(post)) != nil else {
            notice = "삭제하지 못했어요. 목록을 읽을 수 없는 상태예요"
            return
        }
        // 보관 기록도 함께 지운다 — 없는 포스트의 id가 파일에 쌓일 이유가 없다.
        archive.forget(post.id)
        dismiss()
    }

    /* 사진 앱 저장. 원본 JPEG 파일을 그대로 넘긴다.
     * `.addOnly` 권한만 요청한다 — 읽기 권한은 필요하지도 않고 사용자에게 더 큰 요구다. */
    private func saveToPhotos(_ post: ComposedPost) async {
        isSavingToPhotos = true
        defer { isSavingToPhotos = false }
        notice = nil

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            notice = "사진 앱 접근이 허용되지 않았어요. 설정에서 허용할 수 있어요"
            return
        }

        let url = store.imageURL(for: post)
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset()
                    .addResource(with: .photo, fileURL: url, options: nil)
            }
            notice = "사진 앱에 저장했어요"
        } catch {
            notice = "사진 앱에 저장하지 못했어요"
        }
    }
}
