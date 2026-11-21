import UIKit
import SnapKit
import RxSwift
import RxCocoa

final class OCRMarkupViewController: AdaptiveViewController {
    var onConfirm: ((String) -> Void)?

    private let disposeBag = DisposeBag()
    private let capturedImage: UIImage
    private lazy var viewModel = OCRMarkupViewModel(image: capturedImage)
    private let strokes = BehaviorRelay<[[CGPoint]]>(value: [])
    private var selectedText = ""
    private let cancelItem = SystemNavigationStyle.item(image: "xmark", label: "닫기", identifier: "closeOCRButton", priority: .high)
    private let clearItem = SystemNavigationStyle.item(image: "eraser", label: "지우기", identifier: "clearOCRButton")
    private let confirmItem = SystemNavigationStyle.item(image: "checkmark", label: "확인", identifier: "confirmOCRButton", priority: .high)
    private let imageContainerView = UIView()
    private lazy var imageView: UIImageView = {
        let view = UIImageView(image: capturedImage)
        view.contentMode = .scaleAspectFit
        return view
    }()
    private let drawingOverlay = DrawingOverlayView()
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let instructionLabel = UILabel()
    private let statusLabel = UILabel()

    init(image: UIImage) {
        capturedImage = OCRImageGeometry.uprightImage(image)
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .background
        SystemNavigationStyle.configure(self, title: "밑줄 선택")
        navigationItem.leftBarButtonItem = cancelItem
        SystemNavigationStyle.setTrailingItems([confirmItem, clearItem], on: navigationItem)
        setupUI()
        bindActions()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        drawingOverlay.configure(imageRect: OCRImageGeometry.displayRect(imageSize: capturedImage.size, in: imageContainerView.bounds))
    }

    private func setupUI() {
        imageContainerView.clipsToBounds = true
        imageContainerView.layer.cornerRadius = CameraCollectionStyle.previewCornerRadius
        view.addSubview(imageContainerView)
        imageContainerView.addSubview(imageView)
        imageContainerView.addSubview(drawingOverlay)
        imageContainerView.addSubview(activityIndicator)
        activityIndicator.color = .walnut
        activityIndicator.hidesWhenStopped = true
        instructionLabel.text = "밑줄 위에 손가락을 그어 텍스트를 선택하세요"
        instructionLabel.font = CameraCollectionStyle.instructionFont
        instructionLabel.textColor = CameraCollectionStyle.hintColor
        instructionLabel.textAlignment = .center
        instructionLabel.numberOfLines = 0
        instructionLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        view.addSubview(instructionLabel)
        instructionLabel.snp.makeConstraints { make in
            make.top.equalTo(imageContainerView.snp.bottom).offset(16)
            make.leading.trailing.equalTo(view.adaptiveContentLayoutGuide).inset(16)
        }
        statusLabel.font = UIFont(name: "GoyangIlsan R", size: 13) ?? .systemFont(ofSize: 13)
        statusLabel.textColor = UIColor.appPrimary.withAlphaComponent(0.7)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        view.addSubview(statusLabel)
        statusLabel.snp.makeConstraints { make in
            make.leading.trailing.equalTo(view.adaptiveContentLayoutGuide).inset(16)
            make.bottom.equalTo(view.adaptiveContentLayoutGuide).inset(12)
            make.top.greaterThanOrEqualTo(instructionLabel.snp.bottom).offset(12)
        }
        let markupLayoutGuide = UILayoutGuide()
        view.addLayoutGuide(markupLayoutGuide)
        markupLayoutGuide.snp.makeConstraints { make in
            make.top.equalTo(imageContainerView)
            make.bottom.equalTo(instructionLabel)
            make.leading.trailing.equalTo(view.adaptiveContentLayoutGuide)
            make.centerY.equalTo(view.adaptiveContentLayoutGuide).priority(999)
        }
        imageContainerView.snp.makeConstraints { make in
            make.top.greaterThanOrEqualTo(view.adaptiveContentLayoutGuide).offset(8)
            make.centerX.equalTo(view.adaptiveContentLayoutGuide)
            make.leading.greaterThanOrEqualTo(view.adaptiveContentLayoutGuide).offset(8)
            make.trailing.lessThanOrEqualTo(view.adaptiveContentLayoutGuide).offset(-8)
            make.width.equalTo(view.adaptiveContentLayoutGuide.snp.width).offset(-16).priority(998)
            make.height.equalTo(imageContainerView.snp.width).multipliedBy(capturedImage.size.height / capturedImage.size.width)
        }
        imageView.snp.makeConstraints { $0.edges.equalToSuperview() }
        drawingOverlay.snp.makeConstraints { $0.edges.equalToSuperview() }
        activityIndicator.snp.makeConstraints { $0.center.equalToSuperview() }
        drawingOverlay.onStrokesChanged = { [weak self] in self?.strokes.accept($0) }
    }

    private func bindActions() {
        let output = viewModel.transform(input: .init(recognize: .just(()), strokes: strokes.asObservable()))
        output.text.drive(onNext: { [weak self] text in
            self?.selectedText = text
            self?.confirmItem.isEnabled = !text.isEmpty
        }).disposed(by: disposeBag)
        output.hasStrokes.drive(clearItem.rx.isEnabled).disposed(by: disposeBag)
        output.isRecognizing.drive(onNext: { [weak self] busy in
            guard let self else { return }
            if busy { self.activityIndicator.startAnimating() }
            else { self.activityIndicator.stopAnimating() }
            self.drawingOverlay.isUserInteractionEnabled = !busy
        }).disposed(by: disposeBag)
        Driver.combineLatest(output.isRecognizing, output.hasRecognizedText)
            .drive(onNext: { [weak self] busy, hasText in
                self?.statusLabel.text = busy ? "텍스트를 인식하고 있습니다."
                    : hasText ? nil
                    : "텍스트를 감지하지 못했습니다. 다른 사진으로 다시 시도해주세요."
            }).disposed(by: disposeBag)
        output.error.emit(onNext: { [weak self] message in
            guard let self, self.view.window != nil, self.presentedViewController == nil else { return }
            let alert = UIAlertController(title: "텍스트 인식 실패", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "확인", style: .default))
            self.present(alert, animated: true)
        }).disposed(by: disposeBag)
        cancelItem.rx.tap.subscribe(onNext: { [weak self] in
            guard let self else { return }
            (self.navigationController ?? self).dismiss(animated: true)
        }).disposed(by: disposeBag)
        clearItem.rx.tap.subscribe(onNext: { [weak self] in self?.drawingOverlay.clearAll() }).disposed(by: disposeBag)
        confirmItem.rx.tap.subscribe(onNext: { [weak self] in
            guard let self, !self.selectedText.isEmpty else { return }
            let callback = self.onConfirm
            let text = self.selectedText
            (self.navigationController ?? self).dismiss(animated: true) { callback?(text) }
        }).disposed(by: disposeBag)
    }
}

/// 밑줄은 이미지 좌상단을 원점으로 한 0...1 좌표로 보관한다.
/// 뷰 크기가 달라져도 경로를 다시 계산해 그릴 뿐 저장된 선택은 바꾸지 않는다.
private final class DrawingOverlayView: UIView {
    var onStrokesChanged: (([[CGPoint]]) -> Void)?
    private var imageRect = CGRect.zero
    private var completedStrokes: [[CGPoint]] = []
    private var currentStroke: [CGPoint] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(imageRect: CGRect) {
        guard self.imageRect != imageRect else { return }
        // 전환 도중의 미완성 경로도 기존 이미지 좌표로 확정한다.
        finishStroke()
        self.imageRect = imageRect
        setNeedsDisplay()
    }

    func clearAll() {
        completedStrokes = []
        currentStroke = []
        onStrokesChanged?([])
        setNeedsDisplay()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self), imageRect.contains(point),
              let normalized = OCRImageGeometry.normalizedPoint(point, in: imageRect) else { return }
        currentStroke = [normalized]
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !currentStroke.isEmpty, let point = touches.first?.location(in: self),
              let normalized = OCRImageGeometry.normalizedPoint(point, in: imageRect) else { return }
        currentStroke.append(normalized)
        onStrokesChanged?(completedStrokes + [currentStroke])
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if !currentStroke.isEmpty, let point = touches.first?.location(in: self),
           let normalized = OCRImageGeometry.normalizedPoint(point, in: imageRect) {
            currentStroke.append(normalized)
        }
        finishStroke()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { finishStroke() }

    private func finishStroke() {
        guard !currentStroke.isEmpty else { return }
        if currentStroke.count > 1 { completedStrokes.append(currentStroke) }
        currentStroke = []
        onStrokesChanged?(completedStrokes)
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard !imageRect.isEmpty else { return }
        UIColor.appPrimary.setStroke()
        for stroke in completedStrokes + (currentStroke.isEmpty ? [] : [currentStroke]) {
            guard let first = stroke.first else { continue }
            let path = UIBezierPath()
            path.move(to: OCRImageGeometry.viewPoint(first, in: imageRect))
            for point in stroke.dropFirst() { path.addLine(to: OCRImageGeometry.viewPoint(point, in: imageRect)) }
            path.lineWidth = 6
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        }
    }
}
