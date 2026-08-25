/* 컷별 클립을 한 편으로 잇는다 — 발행 직전에 한 번 돈다.
 *
 * `AVMutableComposition`으로 붙이고 통과(passthrough)로 내보낸다. 클립이 전부 같은 설정으로
 * 구워졌으므로(`MotionRecorder`) 다시 인코딩할 이유가 없다 — 6초짜리를 재인코딩하면 발행이
 * 그만큼 늦어지고 화질만 잃는다.
 *
 * 실패하면 nil이다. 영상이 없어도 발행은 그대로 간다(§`MotionRecorder`). */

import AVFoundation

enum MotionComposer {
    struct Result: Sendable {
        let url: URL
        let width: Int
        let height: Int
    }

    static func merge(_ clips: [URL]) async -> Result? {
        guard !clips.isEmpty else { return nil }

        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { return nil }

        var cursor = CMTime.zero
        var naturalSize = CGSize.zero

        for clip in clips {
            let asset = AVURLAsset(url: clip)
            guard let source = try? await asset.loadTracks(withMediaType: .video).first,
                  let duration = try? await asset.load(.duration),
                  duration.isValid, duration > .zero
            else { continue }

            let range = CMTimeRange(start: .zero, duration: duration)
            guard (try? track.insertTimeRange(range, of: source, at: cursor)) != nil else { continue }
            cursor = CMTimeAdd(cursor, duration)

            if naturalSize == .zero, let size = try? await source.load(.naturalSize) {
                naturalSize = size
                // 클립은 촬영 시점에 이미 세로로 돌아온 프레임이라 변환이 항등이다. 그대로 물려준다.
                track.preferredTransform = (try? await source.load(.preferredTransform)) ?? .identity
            }
        }

        guard cursor > .zero, naturalSize != .zero else { return nil }

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("motion-\(UUID().uuidString).mp4")

        guard let export = AVAssetExportSession(
            asset: composition, presetName: AVAssetExportPresetPassthrough
        ) else { return nil }

        do {
            try await export.export(to: output, as: .mp4)
        } catch {
            try? FileManager.default.removeItem(at: output)
            return nil
        }

        return Result(
            url: output,
            width: Int(abs(naturalSize.width)),
            height: Int(abs(naturalSize.height))
        )
    }
}
