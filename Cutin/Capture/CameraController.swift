/* AVFoundation 커스텀 카메라 — expo-camera(`apps/mobile/src/app/capture/camera.tsx`) 대체.
 *
 * 스파이크 검증 항목: 셔터 랙 · 프리뷰 프레임 안정성 · burst 연사 간격이 expo-camera보다 나은가.
 *
 * 스레드 규약 (AVCaptureSession 조작은 메인 스레드를 블로킹하므로 반드시 지킬 것):
 *   - session / photoOutput / isConfigured / pending → `sessionQueue`에서만 만진다
 *   - @Published 프로퍼티 → 메인에서만 쓴다
 * 이 규약 때문에 클래스에 @MainActor를 걸지 않는다. */

import AVFoundation
import UIKit

final class CameraController: NSObject, ObservableObject {
    enum Permission: Equatable {
        case unknown
        case granted
        /// 다시 물어볼 수 있는지 — false면 설정 앱으로 보내야 한다
        case denied(canAskAgain: Bool)
    }

    enum CaptureError: Error {
        case notReady
        case busy
        case noImageData
    }

    @Published private(set) var permission: Permission = .unknown
    @Published private(set) var isFront = true
    @Published private(set) var isRunning = false

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "io.cutin.camera.session")
    private let photoOutput = AVCapturePhotoOutput()

    /// sessionQueue 전용
    private var isConfigured = false
    /// sessionQueue 전용
    private var pending: CheckedContinuation<UIImage, Error>?

    // MARK: - 시작 / 정지

    /// 권한을 확인(필요하면 요청)하고 세션을 올린다. 메인에서 호출한다.
    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permission = .granted
            startSession()

        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.permission = granted ? .granted : .denied(canAskAgain: false)
                    if granted { self.startSession() }
                }
            }

        case .denied, .restricted:
            // 한 번 거부한 뒤에는 앱이 다시 물어볼 수 없다 — 설정 앱으로 보내야 한다
            permission = .denied(canAskAgain: false)

        @unknown default:
            permission = .denied(canAskAgain: false)
        }
    }

    func stop() {
        isRunning = false
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func startSession() {
        let facingFront = isFront
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.isConfigured {
                self.configure(front: facingFront)
                self.isConfigured = true
            }
            if !self.session.isRunning { self.session.startRunning() }

            let running = self.session.isRunning
            DispatchQueue.main.async { self.isRunning = running }
        }
    }

    // MARK: - 세션 구성 (sessionQueue 전용)

    private func configure(front: Bool) {
        session.beginConfiguration()
        session.sessionPreset = .photo

        addInput(front: front)

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .balanced
        }

        session.commitConfiguration()
        applyConnectionSettings(front: front)
    }

    private func addInput(front: Bool) {
        guard let device = Self.device(front: front),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else { return }
        session.addInput(input)
    }

    private static func device(front: Bool) -> AVCaptureDevice? {
        let position: AVCaptureDevice.Position = front ? .front : .back
        return AVCaptureDevice.default(
            front ? .builtInWideAngleCamera : .builtInDualWideCamera,
            for: .video,
            position: position
        ) ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }

    /// 세로 고정 + 전면 미러링 — 원본의 `mirror={facing === "front"}` 대응.
    private func applyConnectionSettings(front: Bool) {
        guard let connection = photoOutput.connection(with: .video) else { return }
        if connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = front
        }
    }

    // MARK: - 전/후면 전환

    func toggleFacing() {
        let next = !isFront
        isFront = next

        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            for input in self.session.inputs { self.session.removeInput(input) }
            self.addInput(front: next)
            self.session.commitConfiguration()
            self.applyConnectionSettings(front: next)
        }
    }

    // MARK: - 촬영

    func capturePhoto() async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self, self.session.isRunning else {
                    continuation.resume(throwing: CaptureError.notReady)
                    return
                }
                guard self.pending == nil else {
                    continuation.resume(throwing: CaptureError.busy)
                    return
                }
                self.pending = continuation

                let settings = AVCapturePhotoSettings()
                settings.photoQualityPrioritization = .balanced
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let result: Result<UIImage, Error>
        if let error {
            result = .failure(error)
        } else if let data = photo.fileDataRepresentation(), let image = UIImage(data: data) {
            result = .success(image)
        } else {
            result = .failure(CaptureError.noImageData)
        }

        // 콜백 큐가 명세되어 있지 않으므로 pending 접근을 sessionQueue로 되돌린다
        sessionQueue.async { [weak self] in
            guard let self, let continuation = self.pending else { return }
            self.pending = nil
            continuation.resume(with: result)
        }
    }
}
