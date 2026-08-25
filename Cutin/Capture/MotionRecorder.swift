/* 촬영 중 기록 — 컷 하나마다 짧은 클립을 파일로 굽는다.
 *
 * QR로 여는 공유 페이지가 이 영상을 보여준다. "네 컷을 찍는 동안 무슨 일이 있었는지"가
 * 인생네컷 QR의 재미이고, 앱을 깔지 않은 사람이 보는 첫 화면이기도 하다.
 *
 * ## 왜 컷별 클립인가
 *
 * 촬영 세션 전체(설정 → 마지막 컷)를 통으로 녹화하면 20~40초·10MB가 넘어 업로드 상한(15MB)에
 * 닿고, 카운트다운을 기다리는 지루한 구간이 대부분을 차지한다. 셔터 직전 1.5초씩만 모으면
 * 4컷이 6초 안팎이고 전부 "찍히는 순간"이다. 사용자 결정(2026-08-25).
 *
 * ## 왜 `AVCaptureMovieFileOutput`이 아닌가
 *
 * 세션에 `AVCapturePhotoOutput`이 이미 붙어 있다. 무비 출력과 사진 출력을 함께 두면 기기에 따라
 * 사진 품질 우선순위가 제한되고, 무엇보다 **녹화 중 사진 촬영이 막히는 조합**이 있다. 이 기능은
 * 사진이 주인공이라 그 위험을 질 수 없다. `AVCaptureVideoDataOutput` + `AVAssetWriter`는 프레임을
 * 직접 받아 쓰므로 사진 경로를 건드리지 않는다.
 *
 * ## 스레드 규약
 *
 * `writer`·`input`·`isArmed` 등 모든 상태는 **`queue`에서만** 만진다. 이 큐가 곧 샘플 버퍼
 * 델리게이트 큐라, 델리게이트 호출과 begin/end가 같은 줄에 서서 락이 필요 없다. */

import AVFoundation
import UIKit

final class MotionRecorder: NSObject, @unchecked Sendable {
    /// 클립 하나의 상한. `end()`가 끝내 불리지 않아도 파일이 무한히 자라지 않게 한다.
    private static let maxClipDuration = CMTime(seconds: 6, preferredTimescale: 600)

    /// 델리게이트 큐이자 상태 큐.
    let queue = DispatchQueue(label: "io.cutin.motion")

    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var sessionStart: CMTime = .invalid
    /// `begin()`은 받았지만 아직 첫 프레임이 오지 않은 상태.
    private var isArmed = false

    /* 720×960(3:4 세로). 사진 프리셋의 프레임은 1440×1920쯤이라 그대로 쓰면 6초에 10MB를 넘는다.
     * 인코더가 알아서 줄이도록 크기를 지정한다 — 스케일 단계를 우리가 돌리지 않는다. */
    private static func videoSettings() -> [String: Any] {
        [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 720,
            AVVideoHeightKey: 960,
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 2_500_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ]
    }

    // MARK: - 구간

    /// 다음 프레임부터 녹화를 시작한다. 이미 녹화 중이면 아무것도 하지 않는다.
    func begin() {
        queue.async { [self] in
            guard writer == nil else { return }
            isArmed = true
        }
    }

    /* 구간을 끝내고 파일을 돌려준다. 녹화가 시작되지 않았거나 실패했으면 nil이다.
     *
     * **nil을 실패로 다루지 않는다.** 영상은 있으면 좋은 것이고, 없다고 촬영이나 발행을 멈추면
     * 카메라 사정 하나로 사진을 잃는다. */
    func end() async -> URL? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                isArmed = false
                guard let writer, let input else {
                    continuation.resume(returning: nil)
                    return
                }
                self.writer = nil
                self.input = nil
                sessionStart = .invalid

                input.markAsFinished()
                let url = writer.outputURL
                /* 완료 콜백 안에서 `writer`를 다시 만지지 않는다 — `AVAssetWriter`는 Sendable이
                 * 아니라 `@Sendable` 클로저가 잡으면 경고가 난다. 성공 여부는 파일이 말한다. */
                writer.finishWriting {
                    let written = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    guard written > 0 else {
                        try? FileManager.default.removeItem(at: url)
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(returning: url)
                }
            }
        }
    }

    /// 진행 중인 구간을 버린다. 화면을 벗어나거나 전/후면을 바꿀 때 부른다.
    func discard() {
        queue.async { [self] in
            isArmed = false
            guard let writer, let input else { return }
            self.writer = nil
            self.input = nil
            sessionStart = .invalid

            input.markAsFinished()
            let url = writer.outputURL
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - 쓰기 (queue 전용)

    private func startWriting(at time: CMTime) -> Bool {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("motion-\(UUID().uuidString).mp4")

        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { return false }

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: Self.videoSettings())
        // 실시간 소스다 — 인코더가 늦으면 프레임을 버리게 둔다. 늦은 프레임을 기다리면 셔터가 밀린다.
        input.expectsMediaDataInRealTime = true

        guard writer.canAdd(input) else { return false }
        writer.add(input)
        guard writer.startWriting() else { return false }
        writer.startSession(atSourceTime: time)

        self.writer = writer
        self.input = input
        sessionStart = time
        return true
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension MotionRecorder: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // 녹화 구간 밖의 프레임은 흘려보낸다. 카메라는 화면이 떠 있는 내내 프레임을 준다.
        guard isArmed || writer != nil else { return }

        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if writer == nil {
            guard startWriting(at: time) else {
                isArmed = false
                return
            }
            isArmed = false
        }

        // 상한을 넘으면 더 쓰지 않는다. 파일은 `end()`가 닫는다.
        guard CMTimeSubtract(time, sessionStart) < Self.maxClipDuration else { return }
        guard let input, input.isReadyForMoreMediaData else { return }
        input.append(sampleBuffer)
    }
}
