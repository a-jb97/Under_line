import UIKit
import SnapKit
import RxSwift
import RxCocoa

final class LaunchAnimationViewController: UIViewController {

    var onCompletion: (() -> Void)?

    private let titleImageView = UIImageView(image: UIImage(named: "LaunchTitle"))
    private let underlineImageView = UIImageView(image: UIImage(named: "LaunchUnderline"))
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

        [titleImageView, underlineImageView, subtitleLabel].forEach(view.addSubview)
        // 로고 글자와 밑줄은 각 요소에 맞게 잘린 별도의 viewBox로 내보낸 이미지
        // scaleAspectFit의 세로 여백을 반영해 밑줄을 'ㅜ'의 가로획에 맞춤
        // 가로획의 중심은 로고 글자의 67 × 74 viewBox에서 y = 51.2
        titleImageView.snp.makeConstraints {
            $0.centerX.equalToSuperview()
            $0.top.equalTo(view.safeAreaLayoutGuide).offset(250)
            $0.width.equalTo(100)
            $0.height.equalTo(100 * 69.0 / 61.0)
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
        underlineImageView.layer.mask = underlineMask

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
        underlineMask.position = .zero
        underlineMask.bounds = CGRect(
            origin: .zero,
            size: CGSize(width: hasStarted ? underlineImageView.bounds.width : 0,
                         height: underlineImageView.bounds.height)
        )
        CATransaction.commit()
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
