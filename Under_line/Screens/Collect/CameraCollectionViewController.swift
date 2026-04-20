//
//  CameraCollectionViewController.swift
//  Under_line
//
//  문장 수집 - 커스텀 카메라 뷰 (Node YNVWL)
//  fabButton 탭 → fullScreen modal 로 present
//

import UIKit
import AVFoundation
import SnapKit
import RxSwift
import RxCocoa

final class CameraCollectionViewController: UIViewController {

    private let disposeBag = DisposeBag()
    private var highlightLayers: [(view: UIView, layer: CAGradientLayer)] = []

    /// directCollectButton 탭 → dismiss 완료 후 호출
    var onDirectCollect: (() -> Void)?

    /// OCR 텍스트 선택 완료 → dismiss 완료 후 추출된 텍스트 전달
    var onOCRTextExtracted: ((String) -> Void)?

    // MARK: - AVFoundation

    private let captureSession = AVCaptureSession()
    private let photoOutput    = AVCapturePhotoOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var currentDevice: AVCaptureDevice?
    private var currentInput: AVCaptureDeviceInput?
    private var isFlashOn = false
    private var usingFrontCamera = false

    private var hasTripleCamera = false

    // MARK: - Top Section

    private let topSectionView: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.background
        return v
    }()

    private lazy var closeButton: UIButton = {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        btn.setImage(UIImage(systemName: "xmark", withConfiguration: cfg), for: .normal)
        btn.tintColor = UIColor.accent
        btn.layer.cornerRadius = 20
        btn.clipsToBounds = true
        return btn
    }()

    private let navTitleLabel: UILabel = {
        let l = UILabel()
        l.text = "밑줄 등록"
        l.font = UIFont(name: "GowunBatang-Bold", size: 18)
            ?? .systemFont(ofSize: 18, weight: .semibold)
        l.textColor = UIColor.accent
        return l
    }()

    private lazy var directCollectButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.attributedTitle = AttributedString(
            "직접 수집",
            attributes: AttributeContainer([
                .font: UIFont(name: "GowunBatang-Bold", size: 12)
                    ?? UIFont.systemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: UIColor.appPrimary,
            ])
        )
        config.baseForegroundColor = UIColor.appPrimary
        config.background.backgroundColor = UIColor.background
        config.background.cornerRadius = 12
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14)
        return UIButton(configuration: config)
    }()

    // MARK: - Camera Section

    private let cameraSectionView: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor(hex: "#1a1a1a")
        v.clipsToBounds = true
        return v
    }()

    private let scanGuideView: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor(white: 1, alpha: 6.0 / 255)
        v.layer.cornerRadius = 12
        v.layer.borderWidth = 1.5
        v.layer.borderColor = UIColor(white: 1, alpha: 64.0 / 255).cgColor
        return v
    }()

    private let scanInstructionLabel: UILabel = {
        let l = UILabel()
        l.text = "밑줄 칠 부분을 촬영해주세요"
        l.font = UIFont(name: "GowunBatang-Regular", size: 14) ?? .systemFont(ofSize: 14)
        l.textColor = UIColor(white: 1, alpha: 0.6)
        l.textAlignment = .center
        return l
    }()

    // MARK: - Bottom Section

    private let bottomSectionView: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.background
        return v
    }()

    private lazy var flashButton: UIButton = {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        btn.setImage(UIImage(systemName: "bolt", withConfiguration: cfg), for: .normal)
        btn.tintColor = UIColor.appPrimary
        btn.layer.cornerRadius = 24
        btn.clipsToBounds = true
        return btn
    }()

    private lazy var captureButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(
            systemName: "camera",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        )
        config.attributedTitle = AttributedString(
            "수집하기",
            attributes: AttributeContainer([
                .font: UIFont(name: "GowunBatang-Bold", size: 18)
                    ?? UIFont.systemFont(ofSize: 18, weight: .semibold),
            ])
        )
        config.imagePlacement = .leading
        config.imagePadding = 10
        config.baseForegroundColor = UIColor.appPrimary
        let btn = UIButton(configuration: config)
        btn.layer.cornerRadius = 32
        btn.clipsToBounds = true
        return btn
    }()

    private lazy var switchCameraButton: UIButton = {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        btn.setImage(UIImage(systemName: "arrow.triangle.2.circlepath.camera", withConfiguration: cfg), for: .normal)
        btn.tintColor = UIColor.appPrimary
        btn.layer.cornerRadius = 24
        btn.clipsToBounds = true
        return btn
    }()

    private let hintLabel: UILabel = {
        let l = UILabel()
        l.text = "촬영하고 나면 밑줄을 그을 수 있습니다"
        l.font = UIFont(name: "GowunBatang-Regular", size: 12) ?? .systemFont(ofSize: 12)
        l.textColor = UIColor.appPrimary.withAlphaComponent(0.6)
        l.textAlignment = .center
        l.numberOfLines = 0
        return l
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(hex: "#1a1a1a")
        setupUI()
        setupConstraints()
        addCornerMarkers()
        bindActions()
        requestCameraPermission()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = cameraSectionView.bounds
        for (view, gradient) in highlightLayers {
            gradient.frame = view.bounds
        }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }

    // MARK: - Setup

    private func setupUI() {
        view.addSubview(topSectionView)
        topSectionView.addSubview(closeButton)
        topSectionView.addSubview(navTitleLabel)
        topSectionView.addSubview(directCollectButton)

        view.addSubview(bottomSectionView)
        bottomSectionView.addSubview(captureButton)
        bottomSectionView.addSubview(flashButton)
        bottomSectionView.addSubview(switchCameraButton)
        bottomSectionView.addSubview(hintLabel)

        view.addSubview(cameraSectionView)
        cameraSectionView.addSubview(scanGuideView)
        cameraSectionView.addSubview(scanInstructionLabel)

        applyGlassStyle(to: flashButton,        cornerRadius: 24)
        applyGlassStyle(to: captureButton,      cornerRadius: 32)
        applyGlassStyle(to: switchCameraButton, cornerRadius: 24)
    }

    private func setupConstraints() {
        // Top section: from screen top down to safeArea.top + 50pt nav header
        topSectionView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.top).offset(50)
        }

        closeButton.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(20)
            make.bottom.equalToSuperview().inset(5)
            make.size.equalTo(40)
        }

        navTitleLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalTo(closeButton)
        }

        directCollectButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(20)
            make.centerY.equalTo(closeButton)
            make.height.equalTo(30)
            make.width.equalTo(76)
        }

        // Bottom section (anchored to screen bottom)
        bottomSectionView.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
        }

        // Camera section fills between top and bottom
        cameraSectionView.snp.makeConstraints { make in
            make.top.equalTo(topSectionView.snp.bottom)
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(bottomSectionView.snp.top)
        }

        // Scan guide: cameraSectionView 기준 leading/trailing/top/bottom inset 40
        let scanGuideInset: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 100 : 48
        scanGuideView.snp.makeConstraints { make in
            make.leading.trailing.top.bottom.equalToSuperview().inset(scanGuideInset)
        }

        scanInstructionLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(scanGuideView.snp.bottom).offset(12)
        }


        // Capture button: centered, 20pt from bottom section top
        captureButton.snp.makeConstraints { make in
            make.top.equalToSuperview().inset(20)
            make.centerX.equalToSuperview()
            make.width.equalTo(200)
            make.height.equalTo(64)
        }

        // Flash / Switch: 24pt gap from capture button edges
        flashButton.snp.makeConstraints { make in
            make.trailing.equalTo(captureButton.snp.leading).offset(-24)
            make.centerY.equalTo(captureButton)
            make.size.equalTo(48)
        }

        switchCameraButton.snp.makeConstraints { make in
            make.leading.equalTo(captureButton.snp.trailing).offset(24)
            make.centerY.equalTo(captureButton)
            make.size.equalTo(48)
        }

        hintLabel.snp.makeConstraints { make in
            make.top.equalTo(captureButton.snp.bottom).offset(20)
            make.leading.trailing.equalToSuperview().inset(24)
            make.bottom.equalTo(view.safeAreaLayoutGuide).inset(40)
        }
    }

    // MARK: - Corner Markers

    private func addCornerMarkers() {
        let len: CGFloat  = 28
        let color = UIColor(white: 1, alpha: 0xAA / 255.0)
        let width: CGFloat = 2.5

        let configs: [(CornerMarkerView.Corner, (ConstraintMaker) -> Void)] = [
            (.topLeft,     { [weak self] make in
                guard let self else { return }
                make.leading.top.equalTo(self.scanGuideView)
            }),
            (.topRight,    { [weak self] make in
                guard let self else { return }
                make.trailing.top.equalTo(self.scanGuideView)
            }),
            (.bottomLeft,  { [weak self] make in
                guard let self else { return }
                make.leading.bottom.equalTo(self.scanGuideView)
            }),
            (.bottomRight, { [weak self] make in
                guard let self else { return }
                make.trailing.bottom.equalTo(self.scanGuideView)
            }),
        ]

        for (corner, constrain) in configs {
            let marker = CornerMarkerView(corner: corner, length: len,
                                          strokeColor: color, strokeWidth: width)
            cameraSectionView.addSubview(marker)
            marker.snp.makeConstraints { make in
                make.size.equalTo(len)
                constrain(make)
            }
        }
    }

    // MARK: - Glass Style (fabButton과 동일한 스타일)

    private func applyGlassStyle(to button: UIButton, cornerRadius: CGFloat) {
        guard let superview = button.superview else { return }

        let shadowView = UIView()
        shadowView.isUserInteractionEnabled = false
        shadowView.layer.cornerRadius = cornerRadius
        shadowView.backgroundColor = .white
        shadowView.layer.shadowColor   = UIColor.black.cgColor
        shadowView.layer.shadowOpacity = Float(CGFloat(0x18) / 255)
        shadowView.layer.shadowRadius  = 8
        shadowView.layer.shadowOffset  = CGSize(width: 0, height: 6)
        superview.insertSubview(shadowView, belowSubview: button)
        shadowView.snp.makeConstraints { $0.edges.equalTo(button) }

        let glassContainer = UIView()
        glassContainer.isUserInteractionEnabled = false
        glassContainer.layer.cornerRadius = cornerRadius
        glassContainer.clipsToBounds = true
        glassContainer.layer.borderWidth = 1
        glassContainer.layer.borderColor = UIColor(white: 1, alpha: CGFloat(0x70) / 255).cgColor
        superview.insertSubview(glassContainer, belowSubview: button)
        glassContainer.snp.makeConstraints { $0.edges.equalTo(button) }
        superview.insertSubview(shadowView, belowSubview: glassContainer)

        let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        blurView.isUserInteractionEnabled = false
        glassContainer.addSubview(blurView)
        blurView.snp.makeConstraints { $0.edges.equalToSuperview() }

        let solidTint = UIView()
        solidTint.isUserInteractionEnabled = false
        solidTint.backgroundColor = UIColor(hex: "#832C11", alpha: CGFloat(0x24) / 255)
        blurView.contentView.addSubview(solidTint)
        solidTint.snp.makeConstraints { $0.edges.equalToSuperview() }

        let topSpecular = UIView()
        topSpecular.isUserInteractionEnabled = false
        blurView.contentView.addSubview(topSpecular)
        topSpecular.snp.makeConstraints { $0.edges.equalToSuperview() }
        let topGrad = CAGradientLayer()
        topGrad.colors = [
            UIColor(white: 1, alpha: CGFloat(0x50) / 255).cgColor,
            UIColor(white: 1, alpha: CGFloat(0x10) / 255).cgColor,
            UIColor.clear.cgColor,
        ]
        topGrad.locations  = [0, 0.45, 1.0]
        topGrad.startPoint = CGPoint(x: 0.5, y: 0)
        topGrad.endPoint   = CGPoint(x: 0.5, y: 1)
        topSpecular.layer.addSublayer(topGrad)
        highlightLayers.append((topSpecular, topGrad))

        let bottomWarm = UIView()
        bottomWarm.isUserInteractionEnabled = false
        blurView.contentView.addSubview(bottomWarm)
        bottomWarm.snp.makeConstraints { $0.edges.equalToSuperview() }
        let bottomGrad = CAGradientLayer()
        bottomGrad.colors = [
            UIColor(hex: "#832C11", alpha: CGFloat(0x20) / 255).cgColor,
            UIColor(hex: "#832C11", alpha: CGFloat(0x0C) / 255).cgColor,
            UIColor.clear.cgColor,
        ]
        bottomGrad.locations  = [0, 0.5, 1.0]
        bottomGrad.startPoint = CGPoint(x: 0.5, y: 1)
        bottomGrad.endPoint   = CGPoint(x: 0.5, y: 0)
        bottomWarm.layer.addSublayer(bottomGrad)
        highlightLayers.append((bottomWarm, bottomGrad))

        button.backgroundColor = .clear
    }

    // MARK: - Camera

    private func requestCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCaptureSession()
        case .notDetermined:
            Task { [weak self] in
                guard let self else { return }
                let granted = await withCheckedContinuation { continuation in
                    AVCaptureDevice.requestAccess(for: .video) { continuation.resume(returning: $0) }
                }
                if granted { self.setupCaptureSession() }
                else { self.showPermissionDeniedAlert() }
            }
        default:
            showPermissionDeniedAlert()
        }
    }

    private func setupCaptureSession() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .photo

        let selectedDevice = usingFrontCamera
            ? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            : bestBackCamera()
        guard let device = selectedDevice,
              let deviceInput = try? AVCaptureDeviceInput(device: device)
        else {
            captureSession.commitConfiguration()
            return
        }

        if captureSession.canAddInput(deviceInput) {
            captureSession.addInput(deviceInput)
            currentDevice = device
            currentInput  = deviceInput
        }

        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        }

        captureSession.commitConfiguration()

        let preview = AVCaptureVideoPreviewLayer(session: captureSession)
        preview.videoGravity = .resizeAspectFill
        preview.frame = cameraSectionView.bounds
        cameraSectionView.layer.insertSublayer(preview, at: 0)
        previewLayer = preview

//        startLensPositionObservation()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
        }
    }

    private func showPermissionDeniedAlert() {
        let alert = UIAlertController(
            title: "카메라 권한 필요",
            message: "카메라 접근 권한이 필요합니다.\n설정에서 허용해주세요.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "설정으로", style: .default) { _ in
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        })
        alert.addAction(UIAlertAction(title: "취소", style: .cancel) { [weak self] _ in
            self?.dismiss(animated: true)
        })
        present(alert, animated: true)
    }

    // MARK: - Bindings

    private func bindActions() {
        closeButton.rx.tap
            .subscribe(onNext: { [weak self] in
                DispatchQueue.global(qos: .userInitiated).async {
                    self?.captureSession.stopRunning()
                }
                self?.dismiss(animated: true)
            })
            .disposed(by: disposeBag)

        flashButton.rx.tap
            .subscribe(onNext: { [weak self] in
                self?.toggleFlash()
            })
            .disposed(by: disposeBag)

        switchCameraButton.rx.tap
            .subscribe(onNext: { [weak self] in
                self?.switchCamera()
            })
            .disposed(by: disposeBag)

        captureButton.rx.tap
            .subscribe(onNext: { [weak self] in
                self?.takePhoto()
            })
            .disposed(by: disposeBag)

        directCollectButton.rx.tap
            .subscribe(onNext: { [weak self] in
                guard let self else { return }
                let callback = self.onDirectCollect
                DispatchQueue.global(qos: .userInitiated).async {
                    self.captureSession.stopRunning()
                }
                self.dismiss(animated: true) { callback?() }
            })
            .disposed(by: disposeBag)
    }

    private func takePhoto() {
        let settings = AVCapturePhotoSettings()
        if let device = currentDevice, device.hasFlash {
            settings.flashMode = isFlashOn ? .on : .off
        }
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    private func toggleFlash() {
        guard let device = currentDevice, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            isFlashOn.toggle()
            device.torchMode = isFlashOn ? .on : .off
            device.unlockForConfiguration()
        } catch {
            print("Flash error: \(error)")
            return
        }
        let iconName = isFlashOn ? "bolt.fill" : "bolt"
        let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        flashButton.setImage(UIImage(systemName: iconName, withConfiguration: cfg), for: .normal)
    }

    private func switchCamera() {
        guard let current = currentInput else { return }
        usingFrontCamera.toggle()

        let selectedDevice: AVCaptureDevice?
        if usingFrontCamera {
            hasTripleCamera = false
            selectedDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        } else {
            selectedDevice = bestBackCamera()
        }
        guard let newDevice = selectedDevice,
              let newInput  = try? AVCaptureDeviceInput(device: newDevice)
        else { return }

        captureSession.beginConfiguration()
        captureSession.removeInput(current)
        if captureSession.canAddInput(newInput) {
            captureSession.addInput(newInput)
            currentDevice = newDevice
            currentInput  = newInput
        }
        captureSession.commitConfiguration()

        // 전면 카메라는 플래시 없으므로 끄기
        if usingFrontCamera && isFlashOn { toggleFlash() }
    }

    private func bestBackCamera() -> AVCaptureDevice? {
        if let triple = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back) {
            hasTripleCamera = true
            return triple
        }
        hasTripleCamera = false
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraCollectionViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil,
              let data  = photo.fileDataRepresentation(),
              let image = UIImage(data: data)
        else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let markupVC = OCRMarkupViewController(image: image)
            markupVC.onConfirm = { [weak self] extractedText in
                guard let self else { return }
                let callback = self.onOCRTextExtracted
                DispatchQueue.global(qos: .userInitiated).async {
                    self.captureSession.stopRunning()
                }
                self.dismiss(animated: true) { callback?(extractedText) }
            }
            self.present(markupVC, animated: true)
        }
    }
}

// MARK: - CornerMarkerView

private final class CornerMarkerView: UIView {

    enum Corner { case topLeft, topRight, bottomLeft, bottomRight }

    private let corner: Corner
    private let markerLength: CGFloat
    private let strokeColor: UIColor
    private let strokeWidth: CGFloat

    init(corner: Corner, length: CGFloat, strokeColor: UIColor, strokeWidth: CGFloat) {
        self.corner       = corner
        self.markerLength = length
        self.strokeColor  = strokeColor
        self.strokeWidth  = strokeWidth
        super.init(frame: .zero)
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        let l = markerLength
        let path = UIBezierPath()

        switch corner {
        case .topLeft:
            path.move(to: CGPoint(x: l, y: 0))
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 0, y: l))
        case .topRight:
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: l, y: 0))
            path.addLine(to: CGPoint(x: l, y: l))
        case .bottomLeft:
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 0, y: l))
            path.addLine(to: CGPoint(x: l, y: l))
        case .bottomRight:
            path.move(to: CGPoint(x: l, y: 0))
            path.addLine(to: CGPoint(x: l, y: l))
            path.addLine(to: CGPoint(x: 0, y: l))
        }

        strokeColor.setStroke()
        path.lineWidth      = strokeWidth
        path.lineCapStyle   = .round
        path.lineJoinStyle  = .round
        path.stroke()
    }
}
