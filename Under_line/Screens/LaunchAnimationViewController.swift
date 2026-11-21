import UIKit
import SnapKit
import RxSwift
import RxCocoa

final class LaunchAnimationViewController: UIViewController {

    var onCompletion: (() -> Void)?

    private let titleImageView = UIImageView(image: UIImage(named: "LaunchTitle"))
    private let underlineContainerView = UIView()
    private let underlineImageView = UIImageView(image: UIImage(named: "LaunchUnderline"))
    private let strokeCoverLayer = CAShapeLayer()
    private let subtitleLabel = UILabel()
    private let underlineMask = CALayer()
    private let disposeBag = DisposeBag()
    private let subtitle = "나만의 문장 수집 기록"
    private var animationTask: Task<Void, Never>?
    private var hasStarted = false
    private var hasCompleted = false
    private var shouldSkipOnReturn = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .background

        titleImageView.contentMode = .scaleAspectFit
        titleImageView.isAccessibilityElement = true
        titleImageView.accessibilityLabel = "밑줄"
        underlineImageView.contentMode = .scaleAspectFit
        underlineImageView.isAccessibilityElement = false

        let subtitleFont = UIFont(name: "GowunBatang-Regular", size: 11) ?? .systemFont(ofSize: 11)
        subtitleLabel.font = subtitleFont
        subtitleLabel.textColor = .appPrimary
        subtitleLabel.textAlignment = .left
        subtitleLabel.isAccessibilityElement = true
        subtitleLabel.accessibilityLabel = subtitle

        [titleImageView, underlineContainerView, subtitleLabel].forEach(view.addSubview)
        underlineContainerView.isUserInteractionEnabled = false
        underlineContainerView.isAccessibilityElement = false
        underlineContainerView.layer.addSublayer(strokeCoverLayer)
        underlineContainerView.addSubview(underlineImageView)
        // 로고 글자와 밑줄은 각 요소에 맞게 잘린 별도의 viewBox로 내보낸 이미지
        // scaleAspectFit의 세로 여백을 반영해 밑줄을 'ㅜ'의 가로획에 맞춤
        // 가로획의 중심은 로고 글자의 67 × 74 viewBox에서 y = 51.2
        titleImageView.snp.makeConstraints {
            $0.centerX.equalToSuperview()
            $0.top.equalTo(view.safeAreaLayoutGuide).offset(250)
            $0.width.equalTo(100)
            $0.height.equalTo(100 * 69.0 / 61.0)
        }
        underlineContainerView.snp.makeConstraints {
            $0.edges.equalTo(titleImageView)
        }
        underlineImageView.snp.makeConstraints {
            $0.leading.equalTo(titleImageView).offset(100 * 4.0 / 61.0)
            let titleScale = 100.0 / 67.0
            let verticalInset = (100 * 69.0 / 61.0 - 74 * titleScale) / 2
            $0.centerY.equalTo(titleImageView.snp.top).offset(verticalInset + 51.2 * titleScale)
            $0.width.equalTo(100 * 53.0 / 61.0)
            $0.height.equalTo(100 * 2.0 / 61.0)
        }
        let subtitleWidth = ceil((subtitle as NSString).size(withAttributes: [
            .font: subtitleFont
        ]).width)
        subtitleLabel.snp.makeConstraints {
            $0.centerX.equalToSuperview()
            $0.top.equalTo(titleImageView.snp.bottom).offset(10)
            $0.width.equalTo(subtitleWidth)
            $0.height.equalTo(20)
        }

        underlineMask.anchorPoint = .zero
        underlineMask.backgroundColor = UIColor.black.cgColor
        // 가림 영역과 갈색 선을 같은 마스크로 노출해 검은 획을 순서대로 덮습니다.
        underlineContainerView.layer.mask = underlineMask

        NotificationCenter.default.rx.notification(UIAccessibility.reduceMotionStatusDidChangeNotification)
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] _ in
                guard UIAccessibility.isReduceMotionEnabled else { return }
                self?.showCompletedLogo()
                self?.finish()
            })
            .disposed(by: disposeBag)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updateStrokeCover()
        underlineMask.position = CGPoint(x: underlineImageView.frame.minX, y: 0)
        underlineMask.bounds = CGRect(
            origin: .zero,
            size: CGSize(width: hasStarted ? underlineImageView.bounds.width : 0,
                         height: underlineContainerView.bounds.height)
        )
        CATransaction.commit()
    }

    private func updateStrokeCover() {
        // 로고 SVG의 좌표를 실제 이미지 표시 영역으로 변환합니다.
        let bounds = titleImageView.bounds
        let scale = min(bounds.width / 67, bounds.height / 74)
        let imageOrigin = CGPoint(x: (bounds.width - 67 * scale) / 2,
                                  y: (bounds.height - 74 * scale) / 2)
        let coverRects = [
            CGRect(x: 29.4, y: 49, width: 15.1, height: 4.2),
            // 중앙은 짧게 가려 'ㅜ' 세로획과 갈색 선의 연결을 보존합니다.
            CGRect(x: 44.5, y: 49, width: 2.2, height: 3),
            CGRect(x: 46.7, y: 49, width: 14.5, height: 4.2)
        ]
        let path = UIBezierPath()
        for rect in coverRects {
            path.append(UIBezierPath(rect: CGRect(
                x: imageOrigin.x + rect.minX * scale,
                y: imageOrigin.y + rect.minY * scale,
                width: rect.width * scale,
                height: rect.height * scale
            )))
        }
        strokeCoverLayer.frame = underlineContainerView.bounds
        strokeCoverLayer.path = path.cgPath
        strokeCoverLayer.fillColor = UIColor.background.resolvedColor(with: traitCollection).cgColor
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startIfNeeded()
    }

    func startIfNeeded() {
        guard isViewLoaded, view.window?.windowScene?.activationState == .foregroundActive,
              !hasCompleted else { return }
        if shouldSkipOnReturn || UIAccessibility.isReduceMotionEnabled {
            showCompletedLogo()
            finish()
            return
        }
        guard !hasStarted else { return }
        view.layoutIfNeeded()
        hasStarted = true

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        underlineMask.bounds.size.width = underlineImageView.bounds.width
        CATransaction.commit()
        let reveal = CABasicAnimation(keyPath: "bounds.size.width")
        reveal.fromValue = 0
        reveal.toValue = underlineImageView.bounds.width
        reveal.duration = 0.4
        reveal.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        underlineMask.add(reveal, forKey: "reveal")

        let characters = Array(subtitle)
        animationTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(400))
                for count in 1...characters.count {
                    try await Task.sleep(for: .seconds(0.6 / Double(characters.count)))
                    guard let self else { return }
                    self.subtitleLabel.text = String(characters.prefix(count))
                }
                try await Task.sleep(for: .milliseconds(500))
                self?.finish()
            } catch {
                // 시작 화면을 벗어나면 진행 중인 타이핑과 완료 처리를 취소
            }
        }
    }

    func cancelForBackground() {
        guard !hasCompleted else { return }
        shouldSkipOnReturn = true
        animationTask?.cancel()
        underlineMask.removeAllAnimations()
    }

    private func showCompletedLogo() {
        hasStarted = true
        underlineMask.removeAllAnimations()
        subtitleLabel.text = subtitle
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }

    private func finish() {
        guard !hasCompleted else { return }
        hasCompleted = true
        animationTask?.cancel()
        underlineMask.removeAllAnimations()
        let completion = onCompletion
        onCompletion = nil
        completion?()
    }

    deinit {
        animationTask?.cancel()
    }
}
