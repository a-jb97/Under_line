//
//  QuoteCardEditorViewController.swift
//  Under_line
//
//  quoteCard 길게 탭 시 표시되는 카드 편집 오버레이
//

import UIKit
import PhotosUI
import SnapKit
import RxSwift
import RxCocoa
import Toast

final class QuoteCardEditorViewController: AdaptiveViewController {

    private let previewContainer = UIView()
    private let previewCanvas = UIView()
    private let actionsScrollView = UIScrollView()
    private var actionCells: [UIView] = []
    private var usesFoldableLayout = false
    private var hasHinge = false
    private struct MaskGeometry: Equatable {
        let size: CGSize
        let scale: CGFloat
    }
    private var maskGeometry: [ObjectIdentifier: MaskGeometry] = [:]
    private let disposeBag = DisposeBag()
    private enum Content {
        case quote(Sentence, bookTitle: String)
        case markedPhoto(UIImage, Data)
    }
    private let content: Content
    private var showsMarkedPhoto: Bool {
        if case .markedPhoto = content { return true }
        return false
    }
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var isDominantColorEnabled = false
    private var dominantTextColor: UIColor = .appPrimary

    init(sentence: Sentence, bookTitle: String) {
        content = .quote(sentence, bookTitle: bookTitle)
        super.init(nibName: nil, bundle: nil)
    }

    init?(markedPhotoData: Data) {
        guard let image = UIImage(data: markedPhotoData) else { return nil }
        content = .markedPhoto(image, markedPhotoData)
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
        btn.tintColor = UIColor.appPrimary
        return btn
    }()

    lazy var backgroundButton: UIButton = {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        btn.setImage(UIImage(systemName: "photo", withConfiguration: cfg), for: .normal)
        btn.tintColor = UIColor.appPrimary
        return btn
    }()

    lazy var colorSyncButton: UIButton = {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        btn.setImage(UIImage(systemName: "paintpalette.fill", withConfiguration: cfg), for: .normal)
        btn.tintColor = UIColor.appPrimary
        btn.isHidden = true
        return btn
    }()

    lazy var saveButton: UIButton = {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let symbol = showsMarkedPhoto ? "square.and.arrow.down" : "square.and.arrow.up"
        btn.setImage(UIImage(systemName: symbol, withConfiguration: cfg), for: .normal)
        btn.tintColor = UIColor.appPrimary
        return btn
    }()

    private let removeLogoLabel = QuoteCardEditorViewController.makeActionLabel("로고 제거")
    private let backgroundLabel = QuoteCardEditorViewController.makeActionLabel("배경 지정")
    private let colorSyncLabel  = QuoteCardEditorViewController.makeActionLabel("색상 동기화")
    private var saveTitle: String { showsMarkedPhoto ? "사진 저장" : "공유하기" }
    private lazy var saveLabel = Self.makeActionLabel(saveTitle)

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
        if #available(iOS 27.1, *) {
            view.addInteraction(UIHingeInteraction { [weak self] _, update in
                guard let self else { return }
                let hasHinge = update.hinge != nil
                guard self.hasHinge != hasHinge else { return }
                self.hasHinge = hasHinge
                self.view.setNeedsUpdateConstraints()
                self.view.setNeedsLayout()
            })
        }
    }

    override func updateViewConstraints() {
        // 접힌 Duo에서는 접힘 영역이 화면 밖에 있을 수 있으므로 힌지 정보도 확인한다.
        let container = ContainerLayout(view: view, reservesInactiveDivisions: true)
        usesFoldableLayout = hasHinge || container.reservedRegions.contains { $0.kind == .division }
        super.updateViewConstraints()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let layout = QuoteCardEditorLayout(availableBounds: view.adaptiveContentLayoutGuide.layoutFrame,
                                           containerBounds: view.bounds,
                                           usesFoldableLayout: usesFoldableLayout,
                                           showsColorSync: !colorSyncButton.isHidden)
        previewContainer.frame = layout.previewFrame
        previewCanvas.bounds = CGRect(origin: .zero, size: QuoteCardEditorLayout.canvasSize)
        previewCanvas.center = CGPoint(x: previewContainer.bounds.midX, y: previewContainer.bounds.midY)
        previewCanvas.transform = CGAffineTransform(scaleX: layout.previewScale, y: layout.previewScale)
        let actionsChanged = actionsScrollView.frame != layout.actionsFrame || actionsScrollView.contentSize != layout.actionsContentSize
        actionsScrollView.frame = layout.actionsFrame
        actionsScrollView.contentSize = layout.actionsContentSize
        if actionsChanged { actionsScrollView.contentOffset = .zero }
        for (index, (cell, frame)) in zip(actionCells, layout.actionFrames).enumerated() {
            cell.isHidden = frame.isEmpty || (showsMarkedPhoto && index != actionCells.count - 1)
            cell.frame = frame
        }
        cardView.layoutIfNeeded()
        [bookTitleBlur].forEach { applyFadeMask(to: $0) }
        applyFadeMask(to: sentenceBlur, cornerRadius: 24)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        showTutorialIfNeeded()
    }

    // MARK: - Setup

    private func setupUI() {
        // dismissButton은 가장 아래 (카드보다 뒤)
        view.addSubview(dismissButton)
        view.addSubview(dimView)
        view.addSubview(previewContainer)
        previewContainer.addSubview(previewCanvas)
        previewCanvas.addSubview(cardView)
        view.addSubview(actionsScrollView)

        labelStack.addArrangedSubview(sentenceLabel)
        labelStack.addArrangedSubview(pageLabel)

        cardView.addSubview(backgroundImageView)
        cardView.addSubview(sentenceBlur)
        cardView.addSubview(bookTitleBlur)
        cardView.addSubview(logoImageView)
        cardView.addSubview(labelStack)
        cardView.addSubview(bookTitleLabel)

        colorSyncLabel.isHidden = true
        let actions = [(removeLogoButton, removeLogoLabel), (backgroundButton, backgroundLabel),
                       (colorSyncButton, colorSyncLabel), (saveButton, saveLabel)]
        for (button, label) in actions {
            let cell = UIView()
            cell.addSubview(button)
            cell.addSubview(label)
            actionsScrollView.addSubview(cell)
            actionCells.append(cell)
            button.snp.makeConstraints { make in
                make.top.equalToSuperview()
                make.centerX.equalToSuperview()
                make.size.equalTo(52)
            }
            label.snp.makeConstraints { make in
                make.top.equalTo(button.snp.bottom).offset(6)
                make.leading.trailing.equalToSuperview()
            }
        }

        SystemGlassButtonStyle.apply(to: removeLogoButton, accessibilityLabel: "로고 제거")
        SystemGlassButtonStyle.apply(to: colorSyncButton, accessibilityLabel: "색상 동기화")
        SystemGlassButtonStyle.apply(to: backgroundButton, accessibilityLabel: "배경 지정")
        SystemGlassButtonStyle.apply(to: saveButton, accessibilityLabel: saveTitle)
    }

    private func setupConstraints() {
        dismissButton.snp.makeConstraints { $0.edges.equalToSuperview() }
        dimView.snp.makeConstraints { $0.edges.equalToSuperview() }

        // 출력용 캔버스는 고정 크기이며 미리보기 축소는 바깥 컨테이너에서만 적용한다.
        cardView.snp.makeConstraints { make in
            make.top.leading.equalToSuperview()
            make.width.equalTo(QuoteCardEditorLayout.canvasSize.width)
            make.height.equalTo(QuoteCardEditorLayout.canvasSize.height)
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
        switch content {
        case let .quote(sentence, _):
            updateTextColor(nil)
            pageLabel.text = "p.\(sentence.page)"
        case let .markedPhoto(image, _):
            cardView.backgroundColor = .black
            backgroundImageView.image = image
            backgroundImageView.contentMode = .scaleAspectFit
            backgroundImageView.isHidden = false
            logoImageView.isHidden = true
            labelStack.isHidden = true
            bookTitleLabel.isHidden = true
        }
    }

    /// dominant가 nil이면 기본 색상(sentence/page → appPrimary, bookTitle → accent),
    /// non-nil이면 세 레이블 모두 dominant color를 적용
    private func updateTextColor(_ dominant: UIColor?) {
        guard case let .quote(sentence, bookTitle) = content else { return }
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

        if case let .markedPhoto(_, data) = content {
            let viewModel = UnderlinePhotoViewModel(photoData: data)
            let output = viewModel.transform(input: .init(saveTap: saveButton.rx.tap
                .do(onNext: { [weak self] in self?.saveButton.isEnabled = false })))
            output.saveMessage
                .emit(onNext: { [weak self] message in
                    self?.saveButton.isEnabled = true
                    self?.view.makeToast(message, position: .center)
                })
                .disposed(by: disposeBag)
            return
        }

        removeLogoButton.rx.tap
            .subscribe(onNext: { [weak self] in
                guard let self else { return }
                let hide = !self.logoImageView.isHidden
                self.logoImageView.isHidden = hide
                let symbolName = hide ? "eye" : "eye.slash"
                let cfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
                var configuration = self.removeLogoButton.configuration
                configuration?.image = SystemGlassButtonStyle.icon(UIImage(systemName: symbolName, withConfiguration: cfg))
                self.removeLogoButton.configuration = configuration
                self.removeLogoButton.accessibilityValue = hide ? "로고 숨김" : "로고 표시"
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
                var configuration = self.colorSyncButton.configuration
                configuration?.image = SystemGlassButtonStyle.icon(UIImage(systemName: icon, withConfiguration: cfg))
                self.colorSyncButton.configuration = configuration
                self.colorSyncButton.accessibilityValue = self.isDominantColorEnabled ? "켜짐" : "꺼짐"
                self.updateTextColor(self.isDominantColorEnabled ? self.dominantTextColor : nil)
            })
            .disposed(by: disposeBag)

        saveButton.rx.tap
            .subscribe(onNext: { [weak self] in self?.shareCard() })
            .disposed(by: disposeBag)
    }

    // MARK: - Blur Fade Mask

    /// 둥근 사각형 마스크를 Gaussian blur로 부드럽게 처리해 자연스러운 pill 형태로 만듦
    /// - parameter cornerRadius: nil이면 pill(height/2), 값을 넘기면 지정 반경의 둥근 사각형
    private func applyFadeMask(to blurView: UIVisualEffectView, cornerRadius: CGFloat? = nil) {
        let s = blurView.bounds.size
        guard s.width > 0, s.height > 0 else { return }

        let scale = cardView.traitCollection.displayScale
        let geometry = MaskGeometry(size: s, scale: scale)
        let key = ObjectIdentifier(blurView)
        guard maskGeometry[key] != geometry || blurView.layer.mask == nil else { return }

        let feather: CGFloat = 25
        let innerRect = CGRect(origin: .zero, size: s).insetBy(dx: feather, dy: feather)
        let cr = cornerRadius ?? innerRect.height / 2

        // 1. 안쪽에 둥근 사각형을 검정으로 그려 날카로운 마스크 이미지 생성
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: s, format: format)
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
        maskGeometry[key] = geometry
    }

    // MARK: - Share Card

    /// 미리보기 축소율과 관계없이 기존 논리 크기와 현재 display scale로 출력한다.
    func renderedCardImage() -> UIImage {
        view.layoutIfNeeded()
        cardView.layoutIfNeeded()
        applyFadeMask(to: sentenceBlur, cornerRadius: 24)
        applyFadeMask(to: bookTitleBlur)
        let format = UIGraphicsImageRendererFormat()
        format.scale = cardView.traitCollection.displayScale
        let bounds = CGRect(origin: .zero, size: QuoteCardEditorLayout.canvasSize)
        return UIGraphicsImageRenderer(bounds: bounds, format: format).image { _ in
            cardView.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
    }

    func makeShareController() -> UIActivityViewController {
        let activityVC = UIActivityViewController(activityItems: [renderedCardImage()], applicationActivities: nil)
        activityVC.popoverPresentationController?.sourceView = saveButton
        activityVC.popoverPresentationController?.sourceRect = saveButton.bounds
        return activityVC
    }

    private func shareCard() {
        present(makeShareController(), animated: true)
    }

    private func setColorSyncVisible(_ visible: Bool) {
        colorSyncButton.isHidden = !visible
        colorSyncLabel.isHidden  = !visible
        view.setNeedsLayout()
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

    func applyBackgroundImage(_ image: UIImage, dominantColor: UIColor) {
        dominantTextColor = dominantColor
        isDominantColorEnabled = false
        let cfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        var configuration = colorSyncButton.configuration
        configuration?.image = SystemGlassButtonStyle.icon(UIImage(systemName: "paintpalette", withConfiguration: cfg))
        colorSyncButton.configuration = configuration
        colorSyncButton.accessibilityValue = "꺼짐"
        backgroundImageView.image = image
        backgroundImageView.isHidden = false
        [sentenceBlur, bookTitleBlur].forEach { $0.isHidden = false }
        setColorSyncVisible(true)
        updateTextColor(nil)
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
                self.applyBackgroundImage(image, dominantColor: dominant)
            }
        }
    }
}

// MARK: - Tutorial

extension QuoteCardEditorViewController {
    private func showTutorialIfNeeded() {
        if showsMarkedPhoto {
            let step = TutorialSupport.viewStep(
                target: saveButton,
                message: "‘사진 저장’을 누르면\n밑줄이 그어진 사진이 사진 앱에 저장돼요."
            )
            TutorialSupport.show(on: self, key: TutorialSupport.markedPhotoSaveKey, steps: [step])
            return
        }
        guard !UserDefaults.standard.bool(forKey: "tutorial.cardEditor") else { return }

        let steps: [TutorialStep] = [
            TutorialStep(
                targetFrame: .zero,
                message: "로고를 숨기거나\n다시 표시할 수 있어요",
                targetFrameProvider: { [weak self] in
                    guard let target = self?.removeLogoButton else { return .zero }
                    return target.convert(target.bounds, to: nil)
                }
            ),
            TutorialStep(
                targetFrame: .zero,
                message: "사진을 배경으로 설정해\n카드를 꾸밀 수 있어요\n\n배경을 지정하면 색상 동기화 버튼이 나타나\n텍스트 색상을 사진의 주요 색상으로 바꿀 수 있어요",
                targetFrameProvider: { [weak self] in
                    guard let target = self?.backgroundButton else { return .zero }
                    return target.convert(target.bounds, to: nil)
                }
            ),
            TutorialStep(
                targetFrame: .zero,
                message: "공유 버튼으로 이미지를 저장하거나\n다른 앱에 공유할 수 있어요",
                targetFrameProvider: { [weak self] in
                    guard let target = self?.saveButton else { return .zero }
                    return target.convert(target.bounds, to: nil)
                }
            ),
        ]

        let tutorialVC = TutorialOverlayViewController()
        tutorialVC.steps = steps
        tutorialVC.modalPresentationStyle = .overFullScreen
        tutorialVC.modalTransitionStyle = .crossDissolve
        tutorialVC.onFinished = {
            UserDefaults.standard.set(true, forKey: "tutorial.cardEditor")
        }
        present(tutorialVC, animated: true)
    }
}
