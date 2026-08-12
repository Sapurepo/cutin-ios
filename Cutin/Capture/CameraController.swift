/* AVFoundation 커스텀 카메라 — expo-camera(`apps/mobile/src/app/capture/camera.tsx`) 대체.
 *
 * 스레드 규약 (AVCaptureSession 조작은 메인 스레드를 블로킹하므로 반드시 지킬 것):
 *   - session / photoOutput / isConfigured / pending → `sessionQueue`에서만 만진다
 *   - 관찰 대상 프로퍼티(permission·isFront·isRunning·failure) → 메인에서만 쓴다
 * 이 규약 때문에 클래스에 @MainActor를 걸지 않고, 대신 규약을 근거로 @unchecked Sendable을 쓴다.
 *
 * 이전 구현에서 고친 것:
 * ① `stop()`/`toggleFacing()`이 진행 중인 continuation을 놔둬 `capturePhoto()`가 영원히
 *    돌아오지 않았다 → 호출부의 `defer { isShooting = false }`가 실행되지 않아 **셔터가 영구 잠김**
 * ② 델리게이트가 끝내 오지 않는 경우(인터럽션 등)에 대한 방어가 없었다 → 워치독 타임아웃
 * ③ 인터럽션·런타임 에러·포그라운드 복귀를 아무도 듣지 않았다 → 통화·백그라운드 후 검은 화면 */

import AVFoundation
import Observation
import UIKit

@Observable
final class CameraController: NSObject, @unchecked Sendable {
    enum Permission: Equatable {
        /// 아직 묻지 않았다 — 앱이 물어볼 수 있다
        case needsRequest
        case granted
        /* 거부됨(또는 기기 정책으로 제한됨). iOS는 한 번 거부된 뒤 앱이 다시 묻는 것을 허용하지
         * 않으므로 남은 길은 설정 앱뿐이다. 이전 구현의 `.denied(canAskAgain: true)`는 어떤
         * 경로로도 만들어지지 않는 상태였다. */
        case denied
    }

    enum CaptureError: Error {
        case notReady
        case busy
        case noImageData
        /// 화면을 벗어나거나 전/후면을 전환해 진행 중인 촬영을 접었다
        case cancelled
        /// 델리게이트가 끝내 오지 않았다 (인터럽션·드라이버 리셋 등)
        case timedOut
    }

    private(set) var permission: Permission = .needsRequest
    private(set) var isFront = true
    private(set) var isRunning = false

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "io.cutin.camera.session")
    private let photoOutput = AVCapturePhotoOutput()
    private var observers: [NSObjectProtocol] = []

    /// 델리게이트가 오지 않을 때 셔터를 풀어주는 상한. 실기기 촬영은 보통 100ms 내외로 끝난다.
    private static let captureTimeout: DispatchTimeInterval = .seconds(5)

    /// sessionQueue 전용
    private var isConfigured = false

    /// sessionQueue 전용. 워치독이 **지난** 촬영을 끊지 않도록 id를 함께 들고 있는다.
    private struct PendingCapture {
        let id: UInt64
        let continuation: CheckedContinuation<UIImage, Error>
    }
    private var pending: PendingCapture?
    private var nextCaptureID: UInt64 = 0

    override init() {
        super.init()
        addObservers()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    // MARK: - 시작 / 정지

    /// 권한을 확인(필요하면 요청)하고 세션을 올린다. 메인에서 호출한다.
    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permission = .granted
            startSession()

        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.permission = granted ? .granted : .denied
                    if granted { self.startSession() }
                }
            }

        case .denied, .restricted:
            permission = .denied

        @unknown default:
            permission = .denied
        }
    }

    func stop() {
        isRunning = false
        sessionQueue.async { [weak self] in
            guard let self else { return }
            // 화면을 벗어나면 델리게이트는 오지 않는다. 기다리는 촬영을 여기서 접어야
            // 호출부의 "촬영 중" 플래그가 풀린다.
            self.resolvePending(.failure(CaptureError.cancelled))
            if self.session.isRunning { self.session.stopRunning() }
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

    // MARK: - 세션 이벤트

    /* 인터럽션(통화·다른 앱의 카메라 사용·분할 화면)과 런타임 에러는 세션을 조용히 멈춘다.
     * 아무도 듣지 않으면 프리뷰가 검은 화면으로 남고 셔터만 눌리지 않는다. */
    private func addObservers() {
        let center = NotificationCenter.default

        observers.append(center.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.isRunning = false
            self.sessionQueue.async { self.resolvePending(.failure(CaptureError.cancelled)) }
        })

        observers.append(center.addObserver(
            forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: .main
        ) { [weak self] _ in
            self?.restartIfNeeded()
        })

        observers.append(center.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: .main
        ) { [weak self] note in
            guard let self else { return }
            self.isRunning = false
            self.sessionQueue.async { self.resolvePending(.failure(CaptureError.notReady)) }

            // 미디어 서비스가 리셋된 경우는 다시 올리면 살아난다.
            let error = note.userInfo?[AVCaptureSessionErrorKey] as? AVError
            if error?.code == .mediaServicesWereReset { self.restartIfNeeded() }
        })

        // 백그라운드에서 돌아왔을 때 세션이 내려가 있으면 다시 올린다.
        observers.append(center.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.restartIfNeeded()
        })
    }

    private func restartIfNeeded() {
        guard permission == .granted, !isRunning else { return }
        startSession()
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
            // 입력을 갈아치우면 진행 중인 촬영의 델리게이트를 기대할 수 없다.
            self.resolvePending(.failure(CaptureError.cancelled))

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

                self.nextCaptureID += 1
                let id = self.nextCaptureID
                self.pending = PendingCapture(id: id, continuation: continuation)
                self.startedAt = DispatchTime.now()

                let settings = AVCapturePhotoSettings()
                settings.photoQualityPrioritization = .balanced
                self.photoOutput.capturePhoto(with: settings, delegate: self)

                // 델리게이트가 오면 pending이 비워지므로 이 타이머는 아무 일도 하지 않는다.
                self.sessionQueue.asyncAfter(deadline: .now() + Self.captureTimeout) { [weak self] in
                    self?.resolvePending(.failure(CaptureError.timedOut), matching: id)
                }
            }
        }
    }

    /// sessionQueue 전용. continuation은 정확히 한 번만 resume되어야 하므로 모든 종료가 여기를 지난다.
    /// `matching`을 주면 그 id의 촬영일 때만 끝낸다 — 워치독이 다음 촬영을 끊지 않게.
    private func resolvePending(_ result: Result<UIImage, Error>, matching id: UInt64? = nil) {
        guard let pending, id == nil || pending.id == id else { return }
        self.pending = nil
        pending.continuation.resume(with: result)
    }

    // MARK: - 실측 (README의 전환 근거 ②를 소급 기록하기 위한 장치)

    /// sessionQueue 전용
    private var startedAt: DispatchTime?
    /// sessionQueue 전용 — 직전 컷이 끝난 시각. 연속 촬영 간격을 재는 기준.
    private var finishedAt: DispatchTime?

    /// sessionQueue 전용
    private func logTiming() {
        #if DEBUG
        let now = DispatchTime.now()
        if let startedAt {
            let latency = Double(now.uptimeNanoseconds - startedAt.uptimeNanoseconds) / 1_000_000
            let gap = finishedAt.map {
                Double(now.uptimeNanoseconds - $0.uptimeNanoseconds) / 1_000_000
            }
            let gapText = gap.map { String(format: " · 직전 컷과 간격 %.0fms", $0) } ?? ""
            print(String(format: "[camera] 셔터 지연 %.0fms", latency) + gapText)
        }
        finishedAt = now
        startedAt = nil
        #endif
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
            guard let self else { return }
            self.logTiming()
            self.resolvePending(result)
        }
    }
}
