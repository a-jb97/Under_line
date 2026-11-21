import AVFoundation
import RxSwift
import RxCocoa

final class CameraCollectionViewModel {
    struct Input {
        let appeared: Observable<Void>
        let disappeared: Observable<Void>
        let capture: Observable<CGFloat>
        let switchCamera: Observable<Void>
        let toggleFlash: Observable<Void>
        let retry: Observable<Void>
    }

    struct State {
        var message: String? = "카메라를 준비하고 있습니다."
        var canCapture = false
        var canSwitch = false
        var supportsFlash = false
        var flashOn = false
        var permissionDenied = false
    }

    struct Output {
        let state: Driver<State>
        let device: Signal<AVCaptureDevice>
        let photo: Signal<Data>
        let error: Signal<String>
    }

    private let disposeBag = DisposeBag()
    private let stateRelay = BehaviorRelay(value: State())
    private let deviceRelay = PublishRelay<AVCaptureDevice>()
    private let photoRelay = PublishRelay<Data>()
    private let errorRelay = PublishRelay<String>()
    private var isVisible = false
    private var requestingPermission = false
    private var deviceID: String?
    private lazy var service = CameraCaptureService { [weak self] event in
        Task { @MainActor [weak self] in self?.handle(event) }
    }

    var session: AVCaptureSession { service.session }

    func transform(input: Input) -> Output {
        Observable.merge(input.appeared, input.retry)
            .subscribe(onNext: { [weak self] in
                self?.isVisible = true
                self?.startIfAuthorized()
            }).disposed(by: disposeBag)
        input.disappeared.subscribe(onNext: { [weak self] in
            self?.isVisible = false
            self?.service.setRunning(false)
        }).disposed(by: disposeBag)
        input.capture.subscribe(onNext: { [weak self] angle in
            guard let self, self.stateRelay.value.canCapture else { return }
            var state = self.stateRelay.value
            state.canCapture = false
            state.canSwitch = false
            self.stateRelay.accept(state)
            self.service.capturePhoto(rotationAngle: angle)
        }).disposed(by: disposeBag)
        input.switchCamera.subscribe(onNext: { [weak self] in self?.service.switchCamera() }).disposed(by: disposeBag)
        input.toggleFlash.subscribe(onNext: { [weak self] in self?.service.toggleFlash() }).disposed(by: disposeBag)
        return Output(state: stateRelay.asDriver(), device: deviceRelay.asSignal(),
                      photo: photoRelay.asSignal(), error: errorRelay.asSignal())
    }

    private func startIfAuthorized() {
        guard !requestingPermission else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            stateRelay.accept(State())
            service.setRunning(true)
        case .notDetermined:
            requestingPermission = true
            Task { [weak self] in
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                guard let self else { return }
                self.requestingPermission = false
                guard self.isVisible else { return }
                if granted { self.startIfAuthorized() }
                else { self.showPermissionDenied() }
            }
        default:
            showPermissionDenied()
        }
    }

    private func showPermissionDenied() {
        var state = State()
        state.message = "카메라 접근이 허용되지 않았습니다. 설정에서 권한을 허용하거나 직접 수집을 이용해주세요."
        state.permissionDenied = true
        stateRelay.accept(state)
    }

    private func handle(_ event: CameraCaptureService.Event) {
        guard isVisible else { return }
        switch event {
        case let .ready(device, flashAvailable, flashOn, canSwitch):
            if device.uniqueID != deviceID {
                deviceID = device.uniqueID
                deviceRelay.accept(device)
            }
            var state = State()
            state.message = nil
            state.canCapture = true
            state.canSwitch = canSwitch
            state.supportsFlash = flashAvailable
            state.flashOn = flashOn
            stateRelay.accept(state)
        case let .unavailable(message):
            var state = State()
            state.message = message
            stateRelay.accept(state)
        case .capturing:
            var state = stateRelay.value
            state.canCapture = false
            state.canSwitch = false
            stateRelay.accept(state)
        case let .photo(data):
            photoRelay.accept(data)
        case let .captureFailed(message):
            errorRelay.accept(message)
        }
    }
}
