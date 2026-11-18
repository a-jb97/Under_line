import UIKit
import AVFoundation
import SnapKit
import RxSwift
import RxCocoa

final class CameraCollectionViewController: AdaptiveViewController {
    var onDirectCollect: (() -> Void)?
    var onOCRTextExtracted: ((String) -> Void)?

    private let disposeBag = DisposeBag()
    private let viewModel = CameraCollectionViewModel()
    private let appeared = PublishRelay<Void>()
    private let disappeared = PublishRelay<Void>()
    private var isVisible = false
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?

    private let closeItem = SystemNavigationStyle.item(image: "xmark", label: "닫기", identifier: "closeCameraButton", priority: .high)
    private let directItem = SystemNavigationStyle.item(image: "square.and.pencil", label: "직접 수집", identifier: "directCollectButton", priority: .high)
    private let cameraSectionView = UIView()
    private let controlsScrollView = ScrollableFormView()
    private let actionRow = UIStackView()
    private let statusStack = UIStackView()
    private let statusLabel = UILabel()
    private let retryButton = UIButton(type: .system)
    private let settingsButton = UIButton(type: .system)
    private let flashButton = UIButton(type: .system)
    private let switchCameraButton = UIButton(type: .system)
    private let captureButton = UIButton(type: .system)
    private let instructionLabel = UILabel()
    private let hintLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(hex: "#1a1a1a")
        SystemNavigationStyle.configure(self, title: "밑줄 등록")
        navigationItem.leftBarButtonItem = closeItem
        SystemNavigationStyle.setTrailingItems([directItem], on: navigationItem)
        setupUI()
        bindActions()
        let preview = AVCaptureVideoPreviewLayer(session: viewModel.session)
        preview.videoGravity = .resizeAspectFill
        cameraSectionView.layer.insertSublayer(preview, at: 0)
        previewLayer = preview
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isVisible = true
        appeared.accept(())
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isVisible = false
        disappeared.accept(())
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let layout = CaptureScreenLayout(availableBounds: view.adaptiveContentLayoutGuide.layoutFrame)
        cameraSectionView.frame = layout.previewFrame
        controlsScrollView.frame = layout.controlsFrame
        let axis: NSLayoutConstraint.Axis = layout.usesSideControls ? .vertical : .horizontal
        if actionRow.axis != axis { actionRow.axis = axis }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer?.frame = cameraSectionView.bounds
        CATransaction.commit()
        updatePreviewRotation()
    }

    private func setupUI() {
        cameraSectionView.clipsToBounds = true
        cameraSectionView.layer.cornerRadius = 12
        controlsScrollView.backgroundColor = .background
        controlsScrollView.layer.cornerRadius = 12
        controlsScrollView.contentInsetAdjustmentBehavior = .never
        view.addSubview(cameraSectionView)
        view.addSubview(controlsScrollView)

        instructionLabel.text = "밑줄 칠 부분을 촬영해주세요"
        instructionLabel.font = UIFont(name: "GowunBatang-Regular", size: 14) ?? .systemFont(ofSize: 14)
        instructionLabel.textColor = .white
        instructionLabel.textAlignment = .center
        instructionLabel.numberOfLines = 0
        cameraSectionView.addSubview(instructionLabel)
        instructionLabel.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview().inset(16)
        }

        statusStack.axis = .vertical
        statusStack.spacing = 12
        statusStack.alignment = .center
        statusLabel.textColor = .white
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.font = .systemFont(ofSize: 14)
        retryButton.setTitle("다시 시도", for: .normal)
        settingsButton.setTitle("설정 열기", for: .normal)
        for button in [retryButton, settingsButton] {
            button.setTitleColor(.white, for: .normal)
            button.snp.makeConstraints { $0.height.greaterThanOrEqualTo(44) }
        }
        [statusLabel, retryButton, settingsButton].forEach(statusStack.addArrangedSubview)
        statusLabel.snp.makeConstraints { $0.width.equalTo(statusStack) }
        cameraSectionView.addSubview(statusStack)
        statusStack.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.leading.trailing.equalToSuperview().inset(16)
        }

        flashButton.setImage(UIImage(systemName: "bolt"), for: .normal)
        switchCameraButton.setImage(UIImage(systemName: "arrow.triangle.2.circlepath.camera"), for: .normal)
        var capture = UIButton.Configuration.plain()
        capture.title = "수집하기"
        capture.image = UIImage(systemName: "camera")
        capture.imagePadding = 8
        capture.baseForegroundColor = .appPrimary
        captureButton.configuration = capture
        SystemGlassButtonStyle.apply(to: flashButton, accessibilityLabel: "플래시")
        SystemGlassButtonStyle.apply(to: captureButton, accessibilityLabel: "수집하기")
        SystemGlassButtonStyle.apply(to: switchCameraButton, accessibilityLabel: "카메라 전환")
        actionRow.axis = .horizontal
        actionRow.spacing = 12
        actionRow.alignment = .center
        [flashButton, captureButton, switchCameraButton].forEach(actionRow.addArrangedSubview)
        for button in [flashButton, switchCameraButton] { button.snp.makeConstraints { $0.size.equalTo(48) } }
        captureButton.snp.makeConstraints { make in
            make.height.equalTo(64)
            make.width.greaterThanOrEqualTo(44)
            make.width.equalTo(140).priority(.high)
        }
        hintLabel.text = "촬영하고 나면 밑줄을 그을 수 있습니다"
        hintLabel.font = UIFont(name: "GowunBatang-Regular", size: 12) ?? .systemFont(ofSize: 12)
        hintLabel.textColor = .appPrimary
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 0
        let stack = UIStackView(arrangedSubviews: [actionRow, hintLabel])
        stack.axis = .vertical
        stack.spacing = 16
        controlsScrollView.formContentView.addSubview(stack)
        stack.snp.makeConstraints { $0.edges.equalToSuperview().inset(12) }
    }

    private func bindActions() {
        let output = viewModel.transform(input: .init(
            appeared: appeared.asObservable(), disappeared: disappeared.asObservable(),
            capture: captureButton.rx.tap.map { [weak self] in
                self?.rotationCoordinator?.videoRotationAngleForHorizonLevelCapture ?? 90
            }, switchCamera: switchCameraButton.rx.tap.asObservable(),
            toggleFlash: flashButton.rx.tap.asObservable(), retry: retryButton.rx.tap.asObservable()
        ))
        output.state.drive(onNext: { [weak self] state in
            guard let self else { return }
            self.statusLabel.text = state.message
            self.statusStack.isHidden = state.message == nil
            self.retryButton.isHidden = state.permissionDenied
            self.settingsButton.isHidden = !state.permissionDenied
            self.instructionLabel.isHidden = state.message != nil
            self.captureButton.isEnabled = state.canCapture
            self.switchCameraButton.isEnabled = state.canSwitch
            self.flashButton.isEnabled = state.supportsFlash && state.canCapture
            for button in [self.captureButton, self.switchCameraButton, self.flashButton] {
                button.alpha = button.isEnabled ? 1 : 0.35
            }
            var config = self.flashButton.configuration
            config?.image = SystemGlassButtonStyle.icon(UIImage(systemName: state.flashOn ? "bolt.fill" : "bolt"))
            self.flashButton.configuration = config
            self.flashButton.accessibilityValue = state.flashOn ? "켜짐" : "꺼짐"
        }).disposed(by: disposeBag)
        output.device.emit(onNext: { [weak self] in self?.configureRotation(device: $0) }).disposed(by: disposeBag)
        output.photo.emit(onNext: { [weak self] data in
            guard let self, let image = UIImage(data: data), self.presentedViewController == nil else { return }
            let markup = OCRMarkupViewController(image: image)
            markup.onConfirm = { [weak self] text in
                guard let self else { return }
                let callback = self.onOCRTextExtracted
                (self.navigationController ?? self).dismiss(animated: true) { callback?(text) }
            }
            let navigation = UINavigationController(rootViewController: markup)
            SystemNavigationStyle.configure(navigation)
            navigation.modalPresentationStyle = .fullScreen
            self.present(navigation, animated: true)
        }).disposed(by: disposeBag)
        output.error.emit(onNext: { [weak self] message in
            guard let self, self.isVisible, self.presentedViewController == nil else { return }
            let alert = UIAlertController(title: "촬영 안내", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "확인", style: .default))
            self.present(alert, animated: true)
        }).disposed(by: disposeBag)
        closeItem.rx.tap.subscribe(onNext: { [weak self] in
            guard let self else { return }
            (self.navigationController ?? self).dismiss(animated: true)
        }).disposed(by: disposeBag)
        directItem.rx.tap.subscribe(onNext: { [weak self] in
            guard let self else { return }
            let callback = self.onDirectCollect
            (self.navigationController ?? self).dismiss(animated: true) { callback?() }
        }).disposed(by: disposeBag)
        settingsButton.rx.tap.subscribe(onNext: {
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        }).disposed(by: disposeBag)
        NotificationCenter.default.rx.notification(UIApplication.didBecomeActiveNotification)
            .filter { [weak self] _ in self?.isVisible == true }
            .subscribe(onNext: { [weak self] _ in self?.appeared.accept(()) }).disposed(by: disposeBag)
        NotificationCenter.default.rx.notification(UIApplication.willResignActiveNotification)
            .filter { [weak self] _ in self?.isVisible == true }
            .subscribe(onNext: { [weak self] _ in self?.disappeared.accept(()) }).disposed(by: disposeBag)
    }

    private func configureRotation(device: AVCaptureDevice) {
        guard let previewLayer else { return }
        rotationObservation = nil
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        rotationCoordinator = coordinator
        if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = device.position == .front
        }
        // RotationCoordinator는 디스플레이 이동도 추적하고 메인 큐에서 KVO를 전달한다.
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.updatePreviewRotation() }
        }
    }

    private func updatePreviewRotation() {
        guard let angle = rotationCoordinator?.videoRotationAngleForHorizonLevelPreview,
              let connection = previewLayer?.connection, connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }
}
