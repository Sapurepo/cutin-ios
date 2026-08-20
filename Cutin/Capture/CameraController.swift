/* AVFoundation 커스텀 카메라 — expo-camera(`apps/mobile/src/app/capture/camera.tsx`) 대체.
 *
 * 스레드 규약 (AVCaptureSession 조작은 메인 스레드를 블로킹하므로 반드시 지킬 것):
 *   - session / photoOutput / isConfigured / pending / videoDevice → `sessionQueue`에서만 만진다
 *   - 관찰 대상 프로퍼티(permission·isFront·isRunning·failure·zoomFactor·minZoom·maxZoom)
 *     와 pinchBaseZoom → 메인에서만 쓴다
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
        /// 사용자 조작으로 접었다 — 화면을 벗어나거나 전/후면을 전환했다. 알릴 실패가 아니다
        case cancelled
        /// 통화·다른 앱의 카메라 사용 등으로 세션이 끊겼다. `cancelled`와 달리 알려야 한다
        case interrupted
        /// 델리게이트가 끝내 오지 않았다
        case timedOut
    }

    private(set) var permission: Permission = .needsRequest
    private(set) var isFront = true
    private(set) var isRunning = false

    /// 권한은 있는데 카메라 입력을 붙이지 못한 상태(다른 앱이 카메라를 쥐고 있는 등).
    /// 프리뷰만 검게 두면 사용자는 앱이 고장 난 줄 알고, 되살릴 방법도 알 수 없다.
    private(set) var isUnavailable = false

    /* 줌 — 메인 전용. 아이폰 카메라처럼 핀치로 당긴다. 표시 배율(`zoomFactor`)과 한계를
     * 화면이 읽는다. 한계는 붙은 기기가 정한다(전면은 후면보다 좁다). 최소 1.0(가장 넓게),
     * 최대는 기기 상한을 5배로 자른다 — 그 이상은 4컷 사진에서 화질이 뭉개져 의미가 없다. */
    private(set) var zoomFactor: CGFloat = 1
    private(set) var minZoom: CGFloat = 1
    private(set) var maxZoom: CGFloat = 1

    /// 당길 여지가 있는가 — 없으면 배율 표시를 숨긴다(전면이 최소=최대인 기기도 있다).
    var canZoom: Bool { maxZoom > minZoom + 0.01 }

    let session = AVCaptureSession()

    @ObservationIgnored private let sessionQueue = DispatchQueue(label: "io.cutin.camera.session")
    @ObservationIgnored private let photoOutput = AVCapturePhotoOutput()
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    /// sessionQueue 전용 — 지금 붙어 있는 비디오 기기. 줌은 이 기기의 `videoZoomFactor`를 만진다.
    @ObservationIgnored private var videoDevice: AVCaptureDevice?
    /// 핀치가 시작될 때의 배율 — 제스처의 배수(magnification)를 여기에 곱한다.
    @ObservationIgnored private var pinchBaseZoom: CGFloat = 1
    /// 기기 상한을 이만큼으로 자른다 — 그 위는 4컷에서 화질이 무너진다.
    private static let zoomCeiling: CGFloat = 5

    /// 메인 전용 — 화면이 카메라를 원하는가. `stop()` 뒤에 포그라운드 복귀 같은 이벤트로
    /// 세션이 되살아나면 프리뷰 없는 화면에서 카메라가 돌아간다(프라이버시 표시등·배터리).
    @ObservationIgnored private var shouldRun = false

    /// 델리게이트가 오지 않을 때 셔터를 풀어주는 상한. 실기기 촬영은 보통 100ms 내외로 끝난다.
    private static let captureTimeout: DispatchTimeInterval = .seconds(5)

    /// sessionQueue 전용
    @ObservationIgnored private var isConfigured = false

    /* sessionQueue 전용. `AVCapturePhotoSettings.uniqueID`를 같이 들고 있는 이유:
     * 워치독이 촬영을 끊은 뒤에도 AVFoundation은 그 촬영의 델리게이트를 나중에 부를 수 있다.
     * id로 짝을 맞추지 않으면 그 늦은 콜백이 **다음** 촬영을 가로채, 앞 컷 사진이 다음 슬롯에
     * 들어가고 뒤 컷의 진짜 콜백은 버려진다. */
    private struct PendingCapture {
        let uniqueID: Int64
        let continuation: CheckedContinuation<UIImage, Error>
    }
    @ObservationIgnored private var pending: PendingCapture?

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        /* 기다리는 촬영이 남아 있으면 여기서 끝낸다. resume 없이 파괴하면
         * "SWIFT TASK CONTINUATION MISUSE"와 함께 호출부 Task가 영원히 깨어나지 않는다.
         * deinit 시점에는 sessionQueue가 self를 강하게 잡고 있지 않으므로 직접 접근이 안전하다. */
        pending?.continuation.resume(throwing: CaptureError.cancelled)
    }

    // MARK: - 시작 / 정지

    /// 권한을 확인(필요하면 요청)하고 세션을 올린다. 메인에서 호출한다.
    func start() {
        shouldRun = true
        // 화면이 살아 있는 동안만 세션 이벤트를 듣는다. 재호출(권한 허용 버튼)에도 중복 등록 없음.
        addObservers()

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
        shouldRun = false
        isRunning = false
        /* self를 강하게 잡는다. weak로 두면 sessionQueue가 바쁜 사이(configure·startRunning은
         * 수백 ms가 걸린다) 컨트롤러가 먼저 해제돼 이 블록이 아무 일도 하지 않고, 기다리는
         * continuation이 resume 없이 파괴된다 — 이 PR이 없애려던 바로 그 잠김이다. */
        sessionQueue.async {
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
                /* 입력이 붙지 않았는데 `isConfigured`를 세우면 이 컨트롤러가 사는 동안 다시
                 * 구성하지 않는다 — 포그라운드 복귀도, 사용자가 다시 시도해도 되살릴 수 없다. */
                guard self.configure(front: facingFront) else {
                    DispatchQueue.main.async {
                        self.isRunning = false
                        self.isUnavailable = true
                    }
                    return
                }
                self.isConfigured = true
            }
            if !self.session.isRunning { self.session.startRunning() }

            let running = self.session.isRunning
            DispatchQueue.main.async {
                self.isRunning = running
                self.isUnavailable = false
            }
        }
    }

    // MARK: - 세션 이벤트

    /* 인터럽션(통화·다른 앱의 카메라 사용·분할 화면)과 런타임 에러는 세션을 조용히 멈춘다.
     * 아무도 듣지 않으면 프리뷰가 검은 화면으로 남고 셔터만 눌리지 않는다. */
    private func addObservers() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default

        observers.append(center.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.isRunning = false
            // 사용자가 접은 게 아니라 끊긴 것이다 — 화면이 알려야 하므로 `cancelled`와 구분한다.
            self.sessionQueue.async { self.resolvePending(.failure(CaptureError.interrupted)) }
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

    /// `shouldRun`을 보는 게 핵심이다. 이걸 빼면 `stop()`이 남긴 상태(`isRunning == false`)와
    /// 구분되지 않아, 촬영 화면을 떠난 뒤 포그라운드 복귀만으로 카메라가 다시 켜진다.
    private func restartIfNeeded() {
        guard shouldRun, permission == .granted, !isRunning else { return }
        startSession()
    }

    // MARK: - 세션 구성 (sessionQueue 전용)

    /// 비디오 입력이 실제로 붙었는지 돌려준다. 입력 없는 세션은 프리뷰도 못 그리고,
    /// 촬영을 시도하면 AVFoundation이 `NSInvalidArgumentException`을 던진다(Swift에서 못 잡는다).
    @discardableResult
    private func configure(front: Bool) -> Bool {
        session.beginConfiguration()
        session.sessionPreset = .photo

        let hasInput = addInput(front: front)

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.maxPhotoQualityPrioritization = .balanced
        }

        session.commitConfiguration()
        applyConnectionSettings(front: front)
        return hasInput
    }

    @discardableResult
    private func addInput(front: Bool) -> Bool {
        guard let device = Self.device(front: front),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else { return false }
        session.addInput(input)
        adoptZoomDevice(device)
        return true
    }

    /// sessionQueue 전용. 새 기기가 붙을 때 줌을 1.0으로 되돌리고 한계를 화면에 알린다.
    private func adoptZoomDevice(_ device: AVCaptureDevice) {
        videoDevice = device
        if (try? device.lockForConfiguration()) != nil {
            device.videoZoomFactor = device.minAvailableVideoZoomFactor
            device.unlockForConfiguration()
        }
        let lo = device.minAvailableVideoZoomFactor
        let hi = min(device.maxAvailableVideoZoomFactor, Self.zoomCeiling)
        DispatchQueue.main.async {
            self.minZoom = lo
            self.maxZoom = max(lo, hi)
            self.zoomFactor = lo
        }
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

            let previous = self.session.inputs
            self.session.beginConfiguration()
            for input in previous { self.session.removeInput(input) }
            let switched = self.addInput(front: next)
            if !switched {
                /* 반대 카메라를 열지 못했다. 그대로 두면 **입력 없는 세션**이 남아 프리뷰가
                 * 검게 죽고 다음 촬영이 예외로 떨어진다. 쓰던 입력을 되돌려 놓는다. */
                for input in previous where self.session.canAddInput(input) {
                    self.session.addInput(input)
                }
            }
            self.session.commitConfiguration()

            let facing = switched ? next : !next
            self.applyConnectionSettings(front: facing)
            if !switched {
                DispatchQueue.main.async { self.isFront = facing }
            }
        }
    }

    // MARK: - 줌

    /// 핀치 시작 — 지금 배율을 기준으로 잡는다(메인). 이 값에 제스처 배수를 곱한다.
    func beginPinch() {
        pinchBaseZoom = zoomFactor
    }

    /// 핀치 진행 — 시작 배율 × 제스처 배수. 아이폰 카메라와 같은 감각.
    func updatePinch(scale: CGFloat) {
        setZoom(pinchBaseZoom * scale)
    }

    /// 배율을 한계 안으로 맞춰 기기에 건다. 화면에는 실제로 걸린 값을 돌려준다.
    func setZoom(_ factor: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDevice else { return }
            let clamped = min(max(factor, device.minAvailableVideoZoomFactor),
                              min(device.maxAvailableVideoZoomFactor, Self.zoomCeiling))
            if (try? device.lockForConfiguration()) != nil {
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
            }
            DispatchQueue.main.async { self.zoomFactor = clamped }
        }
    }

    // MARK: - 촬영

    func capturePhoto() async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [weak self] in
                /* 활성 비디오 연결까지 확인한다. `isRunning`만 보면 입력 없이 돌아가는 세션에
                 * 촬영을 걸게 되고, 그때 AVFoundation은 Swift에서 잡을 수 없는
                 * `NSInvalidArgumentException`("no active and enabled video connection")을 던진다. */
                guard let self, self.session.isRunning,
                      self.photoOutput.connection(with: .video)?.isActive == true
                else {
                    continuation.resume(throwing: CaptureError.notReady)
                    return
                }
                guard self.pending == nil else {
                    continuation.resume(throwing: CaptureError.busy)
                    return
                }

                let settings = AVCapturePhotoSettings()
                settings.photoQualityPrioritization = .balanced

                // AVFoundation이 부여한 uniqueID로 짝을 맞춘다 — 델리게이트가 늦게 와도
                // 그 사진이 어느 촬영의 것인지 알 수 있다.
                let id = settings.uniqueID
                self.pending = PendingCapture(uniqueID: id, continuation: continuation)
                self.startedAt = DispatchTime.now()

                self.photoOutput.capturePhoto(with: settings, delegate: self)

                // 델리게이트가 오면 pending이 비워지므로 이 타이머는 아무 일도 하지 않는다.
                self.sessionQueue.asyncAfter(deadline: .now() + Self.captureTimeout) { [weak self] in
                    self?.resolvePending(.failure(CaptureError.timedOut), matching: id)
                }
            }
        }
    }

    /// sessionQueue 전용. continuation은 정확히 한 번만 resume되어야 하므로 모든 종료가 여기를 지난다.
    /// `matching`을 주면 그 촬영일 때만 끝낸다 — 워치독과 늦은 델리게이트가 다음 촬영을 끊지 않게.
    /// 반환값은 실제로 끝냈는지 여부.
    @discardableResult
    private func resolvePending(
        _ result: Result<UIImage, Error>, matching id: Int64? = nil
    ) -> Bool {
        guard let pending, id == nil || pending.uniqueID == id else { return false }
        self.pending = nil
        pending.continuation.resume(with: result)
        return true
    }

    // MARK: - 실측 (README의 전환 근거 ②를 소급 기록하기 위한 장치)

    /// sessionQueue 전용
    @ObservationIgnored private var startedAt: DispatchTime?
    /// sessionQueue 전용 — 직전 컷이 끝난 시각. 연속 촬영 간격을 재는 기준.
    @ObservationIgnored private var finishedAt: DispatchTime?

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
        let id = photo.resolvedSettings.uniqueID
        sessionQueue.async { [weak self] in
            guard let self else { return }
            // 짝이 맞을 때만 기록한다 — 워치독이 끊은 촬영의 늦은 콜백으로 지연 수치가 오염된다.
            guard self.resolvePending(result, matching: id) else { return }
            self.logTiming()
        }
    }
}
