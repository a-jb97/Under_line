import Foundation
@preconcurrency import AVFoundation

/// 세션 구성·시작·중지·촬영을 하나의 직렬 큐에서 처리한다.
nonisolated final class CameraCaptureService: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    enum Event: @unchecked Sendable {
        case ready(device: AVCaptureDevice, flashAvailable: Bool, flashOn: Bool, canSwitch: Bool)
        case unavailable(String)
        case capturing
        case photo(Data)
        case captureFailed(String)
    }

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.jade.UnderLine.camera", qos: .userInitiated)
    private let output = AVCapturePhotoOutput()
    private let onEvent: @Sendable (Event) -> Void
    private var input: AVCaptureDeviceInput?
    private var usingFront = false
    private var flashOn = false
    private var wantsRunning = false
    private var activeCaptureID: Int64?
    private var observers: [NSObjectProtocol] = []

    init(onEvent: @escaping @Sendable (Event) -> Void) {
        self.onEvent = onEvent
        super.init()
        for name in [AVCaptureSession.wasInterruptedNotification, AVCaptureDevice.wasDisconnectedNotification,
                     AVCaptureDevice.wasConnectedNotification,
                     AVCaptureSession.interruptionEndedNotification, AVCaptureSession.runtimeErrorNotification] {
            let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] note in
                guard let self else { return }
                if name == AVCaptureDevice.wasDisconnectedNotification {
                    guard let device = note.object as? AVCaptureDevice else { return }
                    self.queue.async {
                        guard self.input?.device.uniqueID == device.uniqueID else { return }
                        self.activeCaptureID = nil
                        self.onEvent(.unavailable("카메라 연결이 변경되었습니다. 다시 시도하거나 직접 수집을 이용해주세요."))
                    }
                } else if name == AVCaptureDevice.wasConnectedNotification {
                    self.queue.async {
                        if self.wantsRunning, self.input == nil || self.input?.device.isConnected == false { self.resume() }
                    }
                } else {
                    guard note.object as? AVCaptureSession === self.session else { return }
                    let reset = (note.userInfo?[AVCaptureSessionErrorKey] as? AVError)?.code == .mediaServicesWereReset
                    self.queue.async {
                        if name == AVCaptureSession.wasInterruptedNotification {
                            self.activeCaptureID = nil
                            self.onEvent(.unavailable("카메라 사용이 일시 중단되었습니다. 다른 앱의 카메라 사용을 종료한 뒤 다시 시도해주세요."))
                        } else if name == AVCaptureSession.runtimeErrorNotification && !reset {
                            self.activeCaptureID = nil
                            self.onEvent(.unavailable("카메라 오류가 발생했습니다. 다시 시도하거나 직접 수집을 이용해주세요."))
                        } else if self.wantsRunning {
                            self.activeCaptureID = nil
                            self.resume()
                        }
                    }
                }
            }
            observers.append(token)
        }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        let session = session
        let device = input?.device
        queue.async {
            if let device, device.hasTorch, (try? device.lockForConfiguration()) != nil {
                device.torchMode = .off
                device.unlockForConfiguration()
            }
            if session.isRunning { session.stopRunning() }
        }
    }

    func setRunning(_ running: Bool) {
        queue.async {
            self.wantsRunning = running
            if running { self.resume() }
            else {
                self.activeCaptureID = nil
                self.setTorch(false)
                if self.session.isRunning { self.session.stopRunning() }
            }
        }
    }

    private func resume() {
        guard wantsRunning else { return }
        if input == nil || input?.device.isConnected == false {
            guard configureInput(front: usingFront) else { return }
        }
        guard !session.isInterrupted else {
            onEvent(.unavailable("카메라가 일시 중단되었습니다. 잠시 후 다시 시도해주세요."))
            return
        }
        if !session.isRunning { session.startRunning() }
        guard session.isRunning else {
            onEvent(.unavailable("카메라를 시작할 수 없습니다. 다시 시도하거나 직접 수집을 이용해주세요."))
            return
        }
        setTorch(flashOn)
        publishReady()
    }

    @discardableResult
    private func configureInput(front: Bool) -> Bool {
        let device = front
            ? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            : AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        guard let device, let replacement = try? AVCaptureDeviceInput(device: device) else {
            onEvent(.unavailable("사용할 수 있는 카메라가 없습니다. 직접 수집을 이용해주세요."))
            return false
        }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        let previous = input
        setTorch(false)
        if let previous { session.removeInput(previous) }
        input = nil
        guard session.canAddInput(replacement) else {
            if let previous, session.canAddInput(previous) {
                session.addInput(previous)
                input = previous
            }
            onEvent(.unavailable("카메라를 전환할 수 없습니다. 다시 시도해주세요."))
            return false
        }
        session.addInput(replacement)
        input = replacement
        if !session.outputs.contains(output) {
            guard session.canAddOutput(output) else {
                session.removeInput(replacement)
                input = nil
                onEvent(.unavailable("촬영 출력을 구성할 수 없습니다. 직접 수집을 이용해주세요."))
                return false
            }
            session.addOutput(output)
        }
        usingFront = front
        if !device.hasFlash && !device.hasTorch { flashOn = false }
        return true
    }

    func switchCamera() {
        queue.async {
            guard self.wantsRunning, self.activeCaptureID == nil else { return }
            if self.configureInput(front: !self.usingFront) { self.resume() }
        }
    }

    func toggleFlash() {
        queue.async {
            guard self.session.isRunning, let device = self.input?.device,
                  device.hasFlash || device.hasTorch else { return }
            self.flashOn.toggle()
            self.setTorch(self.flashOn)
            self.publishReady()
        }
    }

    private func setTorch(_ enabled: Bool) {
        guard let device = input?.device, device.hasTorch,
              device.isTorchModeSupported(enabled ? .on : .off) else { return }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            device.torchMode = enabled ? .on : .off
        } catch {
            if enabled { onEvent(.captureFailed("조명을 켤 수 없습니다. 조명 없이 촬영할 수 있습니다.")) }
        }
    }

    private func publishReady() {
        guard let device = input?.device else { return }
        let otherPosition: AVCaptureDevice.Position = usingFront ? .back : .front
        let canSwitch = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: otherPosition) != nil
        onEvent(.ready(device: device, flashAvailable: device.hasFlash || device.hasTorch,
                       flashOn: flashOn, canSwitch: canSwitch))
    }

    func capturePhoto(rotationAngle: CGFloat) {
        queue.async {
            guard self.wantsRunning else { return }
            guard self.activeCaptureID == nil else { self.onEvent(.capturing); return }
            guard self.session.isRunning, !self.session.isInterrupted,
                  let connection = self.output.connection(with: .video), connection.isActive else {
                self.onEvent(.unavailable("촬영할 수 없는 상태입니다. 잠시 후 다시 시도해주세요."))
                return
            }
            if connection.isVideoRotationAngleSupported(rotationAngle) { connection.videoRotationAngle = rotationAngle }
            // OCR 원본은 글자가 반전되지 않도록 저장한다. 전면 미리보기만 미러링한다.
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
            let settings = AVCapturePhotoSettings()
            if self.flashOn, self.output.supportedFlashModes.contains(.on) { settings.flashMode = .on }
            self.activeCaptureID = settings.uniqueID
            self.onEvent(.capturing)
            self.output.capturePhoto(with: settings, delegate: self)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        let captureID = photo.resolvedSettings.uniqueID
        queue.async {
            guard self.activeCaptureID == captureID else { return }
            self.activeCaptureID = nil
            if self.wantsRunning {
                self.publishReady()
                if let data { self.onEvent(.photo(data)) }
                else { self.onEvent(.captureFailed("사진을 처리하지 못했습니다. 다시 촬영해주세요.")) }
            }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        guard error != nil else { return }
        let captureID = resolvedSettings.uniqueID
        queue.async {
            guard self.activeCaptureID == captureID else { return }
            self.activeCaptureID = nil
            if self.wantsRunning {
                self.publishReady()
                self.onEvent(.captureFailed("촬영이 중단되었습니다. 다시 시도해주세요."))
            }
        }
    }
}
