//
//  OCRMarkupViewController.swift
//  Under_line
//
//  촬영 이미지에서 손가락으로 밑줄을 그어 텍스트를 선택하는 화면
//  CameraCollectionViewController → fullScreen modal로 present
//

import UIKit
import Vision
import SnapKit
import RxSwift
import RxCocoa

final class OCRMarkupViewController: UIViewController {

    // MARK: - Callback

    /// 텍스트 선택 확인 후 호출 — selectedText 전달
    var onConfirm: ((String) -> Void)?

    // MARK: - Properties

    private let disposeBag = DisposeBag()
    private let capturedImage: UIImage
    private var observations: [VNRecognizedTextObservation] = []
    // observation + 해당 스트로크의 x범위 매핑 (여러 스트로크 누적)
    private var selectionMap: [(obs: VNRecognizedTextObservation, xRange: ClosedRange<CGFloat>)] = []

    // MARK: - Top Bar

    private let topBar: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.background
        return v
    }()

    private lazy var cancelButton: UIButton = {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        btn.setImage(UIImage(systemName: "xmark", withConfiguration: cfg), for: .normal)
        btn.tintColor = UIColor.accent
        btn.layer.cornerRadius = 20
        btn.clipsToBounds = true
        return btn
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.text = "밑줄 선택"
        l.font = UIFont(name: "GowunBatang-Bold", size: 18)
            ?? .systemFont(ofSize: 18, weight: .semibold)
        l.textColor = UIColor.accent
        return l
    }()

    private lazy var confirmButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.attributedTitle = AttributedString(
            "확인",
            attributes: AttributeContainer([
                .font: UIFont(name: "GowunBatang-Bold", size: 14)
                    ?? UIFont.systemFont(ofSize: 14, weight: .semibold),
                .foregroundColor: UIColor.primary,
            ])
        )
        config.baseForegroundColor = UIColor.primary
        config.background.backgroundColor = UIColor.background
        config.background.cornerRadius = 12
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14)
        let btn = UIButton(configuration: config)
        btn.isEnabled = false
        btn.alpha = 0.35
        return btn
    }()

    // MARK: - Image Area

    private let imageContainerView: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor(hex: "#1a1a1a")
        v.clipsToBounds = true
        return v
    }()

    private lazy var imageView: UIImageView = {
        let iv = UIImageView(image: capturedImage)
        iv.contentMode = .scaleAspectFit
        iv.isUserInteractionEnabled = false
        return iv
    }()

    private let drawingOverlay = DrawingOverlayView()

    private let activityIndicator: UIActivityIndicatorView = {
        let ai = UIActivityIndicatorView(style: .large)
        ai.color = .white
        ai.hidesWhenStopped = true
        return ai
    }()

    // MARK: - Bottom Bar

    private let bottomBar: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.background
        return v
    }()

    private lazy var clearButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.attributedTitle = AttributedString(
            "지우기",
            attributes: AttributeContainer([
                .font: UIFont(name: "GowunBatang-Bold", size: 14)
                    ?? UIFont.systemFont(ofSize: 14, weight: .semibold),
                .foregroundColor: UIColor.accent,
            ])
        )
        config.baseForegroundColor = UIColor.accent
        config.background.backgroundColor = UIColor.background
        config.background.cornerRadius = 12
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14)
        let btn = UIButton(configuration: config)
        btn.isEnabled = false
        btn.alpha = 0.35
        return btn
    }()

    // MARK: - Bottom Hint

    private let hintLabel: UILabel = {
        let l = UILabel()
        l.text = "밑줄 위에 손가락을 그어 텍스트를 선택하세요"
        l.font = UIFont(name: "GoyangIlsan R", size: 13) ?? .systemFont(ofSize: 13)
        l.textColor = UIColor(white: 1, alpha: 0.6)
        l.textAlignment = .center
        l.numberOfLines = 0
        return l
    }()

    // MARK: - Init

    init(image: UIImage) {
        self.capturedImage = image
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(hex: "#1a1a1a")
        setupUI()
        setupConstraints()
        bindActions()
        runOCR()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }

    // MARK: - Setup

    private func setupUI() {
        view.addSubview(topBar)
        topBar.addSubview(cancelButton)
        topBar.addSubview(titleLabel)

        view.addSubview(imageContainerView)
        imageContainerView.addSubview(imageView)
        imageContainerView.addSubview(drawingOverlay)
        imageContainerView.addSubview(activityIndicator)

        view.addSubview(hintLabel)

        view.addSubview(bottomBar)
        bottomBar.addSubview(clearButton)
        bottomBar.addSubview(confirmButton)

        drawingOverlay.onStrokeUpdated = { [weak self] in self?.updateSelection() }
        drawingOverlay.onStrokeEnded   = { [weak self] in self?.updateSelection() }
    }

    private func setupConstraints() {
        topBar.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.top).offset(50)
        }

        cancelButton.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(20)
            make.bottom.equalToSuperview().inset(5)
            make.size.equalTo(40)
        }

        titleLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalTo(cancelButton)
        }

        bottomBar.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide.snp.bottom).offset(-60)
        }

        clearButton.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(20)
            make.top.equalToSuperview().inset(12)
            make.height.equalTo(36)
        }

        confirmButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(20)
            make.centerY.equalTo(clearButton)
            make.height.equalTo(36)
            make.width.equalTo(60)
        }

        hintLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(24)
            make.bottom.equalTo(bottomBar.snp.top).offset(-8)
        }

        imageContainerView.snp.makeConstraints { make in
            make.top.equalTo(topBar.snp.bottom)
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(hintLabel.snp.top).offset(-8)
        }

        imageView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        drawingOverlay.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        activityIndicator.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
    }

    // MARK: - Bindings

    private func bindActions() {
        cancelButton.rx.tap
            .subscribe(onNext: { [weak self] in self?.dismiss(animated: true) })
            .disposed(by: disposeBag)

        clearButton.rx.tap
            .subscribe(onNext: { [weak self] in
                guard let self else { return }
                self.drawingOverlay.clearAll()
                self.selectionMap.removeAll()
                self.updateConfirmButton()
            })
            .disposed(by: disposeBag)

        confirmButton.rx.tap
            .subscribe(onNext: { [weak self] in
                guard let self else { return }
                let imageRect = self.displayRect(for: self.capturedImage, in: self.imageContainerView.bounds)
                let text = self.selectionMap
                    .sorted { lhs, rhs in
                        let yDiff = rhs.obs.boundingBox.midY - lhs.obs.boundingBox.midY
                        if abs(yDiff) > 0.02 { return yDiff < 0 }
                        return lhs.obs.boundingBox.minX < rhs.obs.boundingBox.minX
                    }
                    .compactMap { item -> String? in
                        guard let candidate = item.obs.topCandidates(1).first else { return nil }
                        return self.extractWords(from: candidate, withinXRange: item.xRange, imageRect: imageRect)
                    }
                    .joined(separator: " ")
                self.dismiss(animated: true) { self.onConfirm?(text) }
            })
            .disposed(by: disposeBag)
    }

    /// stroke x 범위에 걸치는 단어만 추출 (Vision word-level bbox 이용)
    private func extractWords(from candidate: VNRecognizedText,
                              withinXRange xRange: ClosedRange<CGFloat>,
                              imageRect: CGRect) -> String? {
        let full = candidate.string
        var result: [Substring] = []
        var idx = full.startIndex

        while idx < full.endIndex {
            while idx < full.endIndex, full[idx] == " " { idx = full.index(after: idx) }
            guard idx < full.endIndex else { break }
            let wordStart = idx
            while idx < full.endIndex, full[idx] != " " { idx = full.index(after: idx) }
            let wordRange = wordStart..<idx

            if let box = (try? candidate.boundingBox(for: wordRange)).flatMap({ $0 }) {
                let rect = viewRect(for: box.boundingBox, imageRect: imageRect)
                if (rect.minX...rect.maxX).overlaps(xRange) {
                    result.append(full[wordRange])
                }
            } else {
                result.append(full[wordRange])
            }
        }

        return result.isEmpty ? nil : result.joined(separator: " ")
    }

    // MARK: - OCR

    private func runOCR() {
        activityIndicator.startAnimating()
        drawingOverlay.isUserInteractionEnabled = false

        guard let cgImage = capturedImage.cgImage else {
            activityIndicator.stopAnimating()
            return
        }

        let request = VNRecognizeTextRequest { [weak self] req, _ in
            DispatchQueue.main.async {
                self?.activityIndicator.stopAnimating()
                self?.drawingOverlay.isUserInteractionEnabled = true
                self?.observations = (req.results as? [VNRecognizedTextObservation]) ?? []
            }
        }
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ko-KR", "en-US"]
        request.usesLanguageCorrection = true

        let orientation = CGImagePropertyOrientation(capturedImage.imageOrientation)
        DispatchQueue.global(qos: .userInitiated).async {
            try? VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
                .perform([request])
        }
    }

    // MARK: - Selection Update

    private func updateSelection() {
        selectionMap.removeAll()

        let imageRect = displayRect(for: capturedImage, in: imageContainerView.bounds)

        // 완료된 스트로크 + 진행 중인 스트로크를 모두 처리
        var allBounds = drawingOverlay.completedBounds
        if let current = drawingOverlay.currentStrokeBounds {
            allBounds.append(current)
        }

        guard !allBounds.isEmpty else {
            updateConfirmButton()
            return
        }

        for strokeBounds in allBounds {
            let strokeXMin = strokeBounds.minX - 8
            let strokeXMax = strokeBounds.maxX + 8
            let xRange: ClosedRange<CGFloat> = strokeXMin...strokeXMax

            let candidates: [(obs: VNRecognizedTextObservation, rect: CGRect)] = observations.compactMap { obs in
                let r = viewRect(for: obs.boundingBox, imageRect: imageRect)
                let xOverlap = r.maxX > strokeXMin && r.minX < strokeXMax
                let yNear    = r.maxY >= strokeBounds.minY - 80 && r.maxY <= strokeBounds.maxY + 20
                guard xOverlap && yNear else { return nil }
                return (obs: obs, rect: r)
            }
            guard !candidates.isEmpty else { continue }

            let closestMaxY = candidates.map { $0.rect.maxY }.max()!
            let matched     = candidates.filter { abs($0.rect.maxY - closestMaxY) <= 12 }

            for item in matched {
                // 같은 observation이 이미 있으면 x범위를 합산, 없으면 추가
                if let idx = selectionMap.firstIndex(where: { $0.obs === item.obs }) {
                    let lo = min(selectionMap[idx].xRange.lowerBound, xRange.lowerBound)
                    let hi = max(selectionMap[idx].xRange.upperBound, xRange.upperBound)
                    selectionMap[idx] = (obs: item.obs, xRange: lo...hi)
                } else {
                    selectionMap.append((obs: item.obs, xRange: xRange))
                }
            }
        }

        updateConfirmButton()
    }

    private func updateConfirmButton() {
        let hasSelection = !selectionMap.isEmpty
        confirmButton.isEnabled = hasSelection

        let hasStrokes = drawingOverlay.hasStrokes
        clearButton.isEnabled = hasStrokes

        UIView.animate(withDuration: 0.15) {
            self.confirmButton.alpha = hasSelection ? 1.0 : 0.35
            self.clearButton.alpha = hasStrokes ? 1.0 : 0.35
        }
    }

    // MARK: - Coordinate Helpers

    /// Vision 정규화 bbox → imageContainerView 내 뷰 좌표계
    private func viewRect(for visionBBox: CGRect, imageRect: CGRect) -> CGRect {
        // Vision: (0,0) = 이미지 왼쪽 하단, y 위로 증가
        let x = imageRect.minX + visionBBox.minX * imageRect.width
        let y = imageRect.minY + (1 - visionBBox.maxY) * imageRect.height
        let w = visionBBox.width  * imageRect.width
        let h = visionBBox.height * imageRect.height
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// scaleAspectFit 기준으로 이미지가 실제 표시되는 rect 계산
    private func displayRect(for image: UIImage, in bounds: CGRect) -> CGRect {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return bounds }
        let scale   = min(bounds.width / size.width, bounds.height / size.height)
        let scaledW = size.width  * scale
        let scaledH = size.height * scale
        return CGRect(
            x: (bounds.width  - scaledW) / 2,
            y: (bounds.height - scaledH) / 2,
            width:  scaledW,
            height: scaledH
        )
    }
}

// MARK: - CGImagePropertyOrientation

private extension CGImagePropertyOrientation {
    init(_ uiOrientation: UIImage.Orientation) {
        switch uiOrientation {
        case .up:            self = .up
        case .down:          self = .down
        case .left:          self = .left
        case .right:         self = .right
        case .upMirrored:    self = .upMirrored
        case .downMirrored:  self = .downMirrored
        case .leftMirrored:  self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default:    self = .up
        }
    }
}

// MARK: - DrawingOverlayView

private final class DrawingOverlayView: UIView {

    var onStrokeUpdated: (() -> Void)?
    var onStrokeEnded: (() -> Void)?

    // 완료된 스트로크들
    private var completedPaths: [UIBezierPath] = []
    private(set) var completedBounds: [CGRect] = []

    // 진행 중인 스트로크
    private var currentPath: UIBezierPath?
    private var currentPoints: [CGPoint] = []
    private(set) var currentStrokeBounds: CGRect?

    var hasStrokes: Bool { !completedPaths.isEmpty || currentPath != nil }

    func clearAll() {
        completedPaths.removeAll()
        completedBounds.removeAll()
        currentPath = nil
        currentPoints.removeAll()
        currentStrokeBounds = nil
        setNeedsDisplay()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let pt = touches.first?.location(in: self) else { return }
        currentPath = UIBezierPath()
        currentPath?.move(to: pt)
        currentPoints = [pt]
        currentStrokeBounds = nil
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let pt = touches.first?.location(in: self) else { return }
        currentPath?.addLine(to: pt)
        currentPoints.append(pt)
        currentStrokeBounds = strokeBounds(for: currentPoints)
        onStrokeUpdated?()
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let pt = touches.first?.location(in: self) {
            currentPath?.addLine(to: pt)
            currentPoints.append(pt)
        }
        if let path = currentPath, let b = strokeBounds(for: currentPoints) {
            completedPaths.append(path)
            completedBounds.append(b)
        }
        currentPath = nil
        currentPoints.removeAll()
        currentStrokeBounds = nil
        onStrokeEnded?()
        setNeedsDisplay()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }

    // MARK: Drawing

    override func draw(_ rect: CGRect) {
        UIColor.primary.setStroke()
        let stroke: (UIBezierPath) -> Void = {
            $0.lineWidth = 6; $0.lineCapStyle = .round; $0.lineJoinStyle = .round; $0.stroke()
        }
        completedPaths.forEach(stroke)
        currentPath.map(stroke)
    }

    // MARK: Private

    private func strokeBounds(for points: [CGPoint]) -> CGRect? {
        guard !points.isEmpty else { return nil }
        let xs = points.map { $0.x }
        let ys = points.map { $0.y }
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }
}
