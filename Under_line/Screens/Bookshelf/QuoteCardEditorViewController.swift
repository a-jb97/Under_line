//
//  QuoteCardEditorViewController.swift
//  Under_line
//
//  quoteCard 길게 탭 시 표시되는 카드 편집 오버레이
//

import UIKit
import Photos
import PhotosUI
import SnapKit
import RxSwift
import RxCocoa
import Toast

final class QuoteCardEditorViewController: UIViewController {

    private let disposeBag = DisposeBag()
    private let sentence: Sentence
    private let bookTitle: String
    private var highlightLayers: [(view: UIView, layer: CAGradientLayer)] = []
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var isDominantColorEnabled = false
    private var dominantTextColor: UIColor = .appPrimary
    private var colorSyncDecorations: [UIView] = []

    init(sentence: Sentence, bookTitle: String) {
        self.sentence  = sentence
        self.bookTitle = bookTitle
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Views

    /// 카드 바깥 어두운 영역 탭 → dismiss (Rule 3: UIButton, not UIView+gesture)
    private let dismissButton: UIButton = {
        let btn = UIButton(type: .custom)
        btn.backgroundColor = .clear
        return btn
    }()

    private let dimView: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        v.isUserInteractionEnabled = false
        return v
    }()

    // 카드 본체 — 비율 1:1.586 (신용카드)
    let cardView: UIView = {
        let v = UIView()
        v.backgroundColor = .white
        v.layer.cornerRadius  = 16
        v.layer.shadowColor   = UIColor.black.cgColor
        v.layer.shadowOpacity = Float(CGFloat(0x26) / 255)
        v.layer.shadowRadius  = 12
        v.layer.shadowOffset  = CGSize(width: 0, height: 8)
        return v
    }()

    let backgroundImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 16
        iv.isHidden = true
        iv.isUserInteractionEnabled = false
        return iv
    }()

    let logoImageView: UIImageView = {
        let iv = UIImageView()
        iv.image = UIImage(named: "Under_line_Logo")
        iv.contentMode = .scaleAspectFit
        iv.isUserInteractionEnabled = false
        return iv
    }()

    private let sentenceLabel: UILabel = {
        let l = UILabel()
        l.numberOfLines = 0
        l.textAlignment = .center
        l.isUserInteractionEnabled = false
        return l
    }()

    // MARK: - Text Blur Backgrounds (사진 배경 설정 시 가독성 보조)

    private let sentenceBlur  = QuoteCardEditorViewController.makeTextBlurView()
    private let bookTitleBlur = QuoteCardEditorViewController.makeTextBlurView()

    private static func makeTextBlurView() -> UIVisualEffectView {
        let v = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        v.isHidden = true
        v.isUserInteractionEnabled = false
        return v
    }

    private let pageLabel: UILabel = {
        let l = UILabel()
        l.font = UIFont(name: "GoyangIlsan R", size: 13) ?? .systemFont(ofSize: 13)
        l.textColor = UIColor.appPrimary
        l.textAlignment = .right
        l.isUserInteractionEnabled = false
        return l
    }()

    private let labelStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.alignment = .fill
        sv.spacing = 12
        sv.isUserInteractionEnabled = false
        return sv
    }()

    private let bookTitleLabel: UILabel = {
        let l = UILabel()
        l.numberOfLines = 1
        l.textAlignment = .center
        l.adjustsFontSizeToFitWidth = true
        l.minimumScaleFactor = 0.7
        l.isUserInteractionEnabled = false
        return l
    }()

    // MARK: - Action Buttons

    lazy var removeLogoButton: UIButton = {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        btn.setImage(UIImage(systemName: "eye.slash", withConfiguration: cfg), for: .normal)
        btn.tintColor = UIColor.walnut
        btn.layer.cornerRadius = 26
        btn.clipsToBounds = true
        return btn
    }()

    lazy var backgroundButton: UIButton = {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        btn.setImage(UIImage(systemName: "photo", withConfiguration: cfg), for: .normal)
        btn.tintColor = UIColor.walnut
        btn.layer.cornerRadius = 26
        btn.clipsToBounds = true
        return btn
    }()

    lazy var colorSyncButton: UIButton = {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        btn.setImage(UIImage(systemName: "paintpalette.fill", withConfiguration: cfg), for: .normal)
        btn.tintColor = UIColor.walnut
        btn.layer.cornerRadius = 26
        btn.clipsToBounds = true
        btn.isHidden = true
        return btn
    }()

    lazy var saveButton: UIButton = {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        btn.setImage(UIImage(systemName: "square.and.arrow.down", withConfiguration: cfg), for: .normal)
        btn.tintColor = UIColor.walnut
        btn.layer.cornerRadius = 26
        btn.clipsToBounds = true
        return btn
    }()

    private let removeLogoLabel = QuoteCardEditorViewController.makeActionLabel("로고 제거")
    private let backgroundLabel = QuoteCardEditorViewController.makeActionLabel("배경 지정")
    private let colorSyncLabel  = QuoteCardEditorViewController.makeActionLabel("색상 동기화")
    private let saveLabel       = QuoteCardEditorViewController.makeActionLabel("카드 생성")

    private static func makeActionLabel(_ text: String) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = UIFont(name: "GoyangIlsan R", size: 10) ?? .systemFont(ofSize: 10)
        l.textColor = UIColor.white.withAlphaComponent(0.8)
        l.textAlignment = .center
        return l
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        setupUI()
        setupConstraints()
        configure()
        bindActions()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        for (view, gradient) in highlightLayers {
            gradient.frame = view.bounds
        }
        [bookTitleBlur].forEach { applyFadeMask(to: $0) }
        applyFadeMask(to: sentenceBlur, cornerRadius: 24)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    // MARK: - Setup

    private func setupUI() {
        // dismissButton은 가장 아래 (카드보다 뒤)
        view.addSubview(dismissButton)
        view.addSubview(dimView)
        view.addSubview(cardView)

        labelStack.addArrangedSubview(sentenceLabel)
        labelStack.addArrangedSubview(pageLabel)

        cardView.addSubview(backgroundImageView)
        cardView.addSubview(sentenceBlur)
        cardView.addSubview(bookTitleBlur)
        cardView.addSubview(logoImageView)
        cardView.addSubview(labelStack)
        cardView.addSubview(bookTitleLabel)

        view.addSubview(removeLogoButton)
        view.addSubview(backgroundButton)
        view.addSubview(colorSyncButton)
        view.addSubview(saveButton)
        view.addSubview(removeLogoLabel)
        view.addSubview(backgroundLabel)
        colorSyncLabel.isHidden = true
        view.addSubview(colorSyncLabel)
        view.addSubview(saveLabel)

        applyFabGlassStyle(to: removeLogoButton, cornerRadius: 26)
        applyFabGlassStyle(to: backgroundButton, cornerRadius: 26)
        colorSyncDecorations = applyFabGlassStyle(to: colorSyncButton, cornerRadius: 26)
        colorSyncDecorations.forEach { $0.isHidden = true }
        applyFabGlassStyle(to: saveButton,        cornerRadius: 26)
    }

    private func setupConstraints() {
        dismissButton.snp.makeConstraints { $0.edges.equalToSuperview() }
        dimView.snp.makeConstraints { $0.edges.equalToSuperview() }

        // 버튼 레이블: safeArea 하단 기준
        removeLogoLabel.snp.makeConstraints { make in
            make.centerX.equalTo(removeLogoButton)
            make.bottom.equalTo(view.safeAreaLayoutGuide).inset(16)
        }
        backgroundLabel.snp.makeConstraints { make in
            make.centerX.equalTo(backgroundButton)
            make.bottom.equalTo(removeLogoLabel)
        }
        colorSyncLabel.snp.makeConstraints { make in
            make.centerX.equalTo(colorSyncButton)
            make.bottom.equalTo(removeLogoLabel)
        }
        saveLabel.snp.makeConstraints { make in
            make.centerX.equalTo(saveButton)
            make.bottom.equalTo(removeLogoLabel)
        }

        // 버튼: 레이블 바로 위
        removeLogoButton.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(24)
            make.bottom.equalTo(removeLogoLabel.snp.top).offset(-6)
            make.size.equalTo(52)
        }
        backgroundButton.snp.makeConstraints { make in
            make.leading.equalTo(removeLogoButton.snp.trailing).offset(12)
            make.centerY.equalTo(removeLogoButton)
            make.size.equalTo(52)
        }
        colorSyncButton.snp.makeConstraints { make in
            make.leading.equalTo(backgroundButton.snp.trailing).offset(12)
            make.centerY.equalTo(removeLogoButton)
            make.size.equalTo(52)
        }
        saveButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(24)
            make.centerY.equalTo(removeLogoButton)
            make.size.equalTo(52)
        }

        // 카드: 버튼 그룹 위 24pt 간격, 좌우 inset 32, 비율 1:1.586
        cardView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(32)
            make.height.equalTo(cardView.snp.width).multipliedBy(1.586)
            make.center.equalToSuperview()
        }

        // 카드 내부
        backgroundImageView.snp.makeConstraints { $0.edges.equalToSuperview() }

        sentenceBlur.snp.makeConstraints { make in
            make.leading.trailing.equalTo(labelStack).inset(-40)
            make.top.equalTo(labelStack).inset(-24)
            make.bottom.equalTo(labelStack.snp.bottom).inset(-44)
        }
        bookTitleBlur.snp.makeConstraints { $0.edges.equalTo(bookTitleLabel).inset(-28) }

        logoImageView.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(17)
            make.top.equalToSuperview().inset(12)
            make.width.equalTo(22)
            make.height.equalTo(26)
        }

        labelStack.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(24)
            make.centerY.equalToSuperview()
            make.bottom.lessThanOrEqualTo(bookTitleLabel.snp.top).offset(-8)
        }

        bookTitleLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.width.lessThanOrEqualToSuperview().inset(24)
            make.bottom.equalToSuperview().inset(16)
        }
        bookTitleLabel.setContentHuggingPriority(.required, for: .horizontal)
    }

    // MARK: - Configure

    private func configure() {
        updateTextColor(nil)
        pageLabel.text = "p.\(sentence.page)"
    }

    /// dominant가 nil이면 기본 색상(sentence/page → appPrimary, bookTitle → accent),
    /// non-nil이면 세 레이블 모두 dominant color를 적용
    private func updateTextColor(_ dominant: UIColor?) {
        let bodyColor  = dominant ?? .appPrimary
        let titleColor = dominant ?? .accent

        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.7
        style.alignment = .center
        style.lineBreakStrategy = .hangulWordPriority
        sentenceLabel.attributedText = NSAttributedString(
            string: sentence.sentence,
            attributes: [
                .font:            UIFont(name: "GowunBatang-Regular", size: 18) ?? .systemFont(ofSize: 18),
                .foregroundColor: bodyColor,
                .paragraphStyle:  style,
            ]
        )
        pageLabel.textColor = bodyColor

        bookTitleLabel.attributedText = NSAttributedString(
            string: bookTitle,
            attributes: [
                .font:            UIFont(name: "GowunBatang-Regular", size: 13) ?? .systemFont(ofSize: 13),
                .foregroundColor: titleColor,
            ]
        )
    }

    // MARK: - Bindings

    private func bindActions() {
        dismissButton.rx.tap
            .subscribe(onNext: { [weak self] in self?.dismiss(animated: true) })
            .disposed(by: disposeBag)

        removeLogoButton.rx.tap
            .subscribe(onNext: { [weak self] in
                guard let self else { return }
                let hide = !self.logoImageView.isHidden
                self.logoImageView.isHidden = hide
                let symbolName = hide ? "eye" : "eye.slash"
                let cfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
                self.removeLogoButton.setImage(UIImage(systemName: symbolName, withConfiguration: cfg), for: .normal)
            })
            .disposed(by: disposeBag)

        backgroundButton.rx.tap
            .subscribe(onNext: { [weak self] in self?.presentImagePicker() })
            .disposed(by: disposeBag)

        colorSyncButton.rx.tap
            .subscribe(onNext: { [weak self] in
                guard let self else { return }
                self.isDominantColorEnabled.toggle()
                let icon = self.isDominantColorEnabled ? "paintpalette.fill" : "paintpalette"
                let cfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
                self.colorSyncButton.setImage(UIImage(systemName: icon, withConfiguration: cfg), for: .normal)
                self.updateTextColor(self.isDominantColorEnabled ? self.dominantTextColor : nil)
            })
            .disposed(by: disposeBag)

        saveButton.rx.tap
            .subscribe(onNext: { [weak self] in self?.saveCardToPhotos() })
            .disposed(by: disposeBag)
    }

    // MARK: - Blur Fade Mask

    /// 둥근 사각형 마스크를 Gaussian blur로 부드럽게 처리해 자연스러운 pill 형태로 만듦
    /// - parameter cornerRadius: nil이면 pill(height/2), 값을 넘기면 지정 반경의 둥근 사각형
    private func applyFadeMask(to blurView: UIVisualEffectView, cornerRadius: CGFloat? = nil) {
        let s = blurView.bounds.size
        guard s.width > 0, s.height > 0 else { return }

        let feather: CGFloat = 25
        let innerRect = CGRect(origin: .zero, size: s).insetBy(dx: feather, dy: feather)
        let cr = cornerRadius ?? innerRect.height / 2

        // 1. 안쪽에 둥근 사각형을 검정으로 그려 날카로운 마스크 이미지 생성
        let renderer = UIGraphicsImageRenderer(size: s)
        let sharpImage = renderer.image { _ in
            UIColor.black.setFill()
            UIBezierPath(roundedRect: innerRect, cornerRadius: cr).fill()
        }

        // 2. CIGaussianBlur로 가장자리를 부드럽게 처리
        guard let ciImage = CIImage(image: sharpImage),
              let blurFilter = CIFilter(name: "CIGaussianBlur") else { return }
        blurFilter.setValue(ciImage, forKey: kCIInputImageKey)
        blurFilter.setValue(feather * 1.0, forKey: kCIInputRadiusKey)
        guard let output = blurFilter.outputImage,
              let cgImage = ciContext.createCGImage(output, from: ciImage.extent) else { return }

        let maskLayer = CALayer()
        maskLayer.frame = CGRect(origin: .zero, size: s)
        maskLayer.contents = cgImage
        blurView.layer.mask = maskLayer
    }

    // MARK: - FAB Glass Style (BookDetailViewController와 동일한 스펙)

    @discardableResult
    private func applyFabGlassStyle(to button: UIButton, cornerRadius: CGFloat) -> [UIView] {
        guard let superview = button.superview else { return [] }

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
        return [shadowView, glassContainer]
    }

    // MARK: - Save Card

    private func saveCardToPhotos() {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard let self else { return }
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    self.view.makeToast("사진 저장 권한이 필요합니다.", duration: 2.0, position: .center)
                }
                return
            }
            // drawHierarchy 등 UI 작업은 반드시 메인 스레드에서 실행
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let format = UIGraphicsImageRendererFormat()
                format.scale = UIScreen.main.scale
                let renderer = UIGraphicsImageRenderer(bounds: self.cardView.bounds, format: format)
                let image = renderer.image { _ in
                    self.cardView.drawHierarchy(in: self.cardView.bounds, afterScreenUpdates: true)
                }
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }) { [weak self] success, _ in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        if success {
                            self.view.makeToast("카드가 저장되었습니다.", duration: 1.5, position: .center) { _ in
                                self.dismiss(animated: true)
                            }
                        } else {
                            self.view.makeToast("저장에 실패했습니다.", duration: 2.0, position: .center)
                        }
                    }
                }
            }
        }
    }

    private func setColorSyncVisible(_ visible: Bool) {
        colorSyncButton.isHidden = !visible
        colorSyncLabel.isHidden  = !visible
        colorSyncDecorations.forEach { $0.isHidden = !visible }
    }

    // MARK: - Dominant Color

    /// 이미지를 50×50으로 축소해 픽셀을 32단계로 양자화한 뒤 가장 빈번한 색을 반환
    private func dominantColor(from image: UIImage) -> UIColor {
        let size = CGSize(width: 50, height: 50)
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * Int(size.width)
        var pixelData = [UInt8](repeating: 0, count: Int(size.width) * Int(size.height) * bytesPerPixel)

        guard let context = CGContext(
            data: &pixelData,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let cgImage = image.cgImage else { return .appPrimary }

        context.draw(cgImage, in: CGRect(origin: .zero, size: size))

        var counts: [UInt32: Int] = [:]
        for i in 0 ..< Int(size.width) * Int(size.height) {
            let o = i * bytesPerPixel
            guard pixelData[o + 3] > 10 else { continue }
            let r = UInt32(pixelData[o])     / 32
            let g = UInt32(pixelData[o + 1]) / 32
            let b = UInt32(pixelData[o + 2]) / 32
            counts[(r << 16) | (g << 8) | b, default: 0] += 1
        }

        guard let key = counts.max(by: { $0.value < $1.value })?.key else { return .appPrimary }
        let r = CGFloat((key >> 16) * 32 + 16) / 255
        let g = CGFloat(((key >> 8) & 0xFF) * 32 + 16) / 255
        let b = CGFloat((key & 0xFF) * 32 + 16) / 255
        return UIColor(red: r, green: g, blue: b, alpha: 1)
    }

    // MARK: - Image Picker

    private func presentImagePicker() {
        var config = PHPickerConfiguration()
        config.selectionLimit = 1
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }
}

// MARK: - PHPickerViewControllerDelegate

extension QuoteCardEditorViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        dismiss(animated: true)
        guard let provider = results.first?.itemProvider,
              provider.canLoadObject(ofClass: UIImage.self) else { return }
        provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            guard let self, let image = object as? UIImage else { return }
            let dominant = self.dominantColor(from: image)
            DispatchQueue.main.async {
                self.dominantTextColor = dominant
                self.isDominantColorEnabled = false
                let cfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
                self.colorSyncButton.setImage(
                    UIImage(systemName: "paintpalette", withConfiguration: cfg), for: .normal
                )
                self.backgroundImageView.image = image
                self.backgroundImageView.isHidden = false
                [self.sentenceBlur, self.bookTitleBlur]
                    .forEach { $0.isHidden = false }
                self.setColorSyncVisible(true)
                self.updateTextColor(nil)
            }
        }
    }
}
