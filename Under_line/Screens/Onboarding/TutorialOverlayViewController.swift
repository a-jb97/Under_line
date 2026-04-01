//
//  TutorialOverlayViewController.swift
//  Under_line
//
//  실제 앱 화면 위에 딤 오버레이 + 말풍선으로 기능을 설명하는 코치마크 온보딩.
//  modalPresentationStyle = .overFullScreen 으로 present 하면
//  하단 앱 화면이 그대로 보이면서 위에 오버레이가 덮임.
//

import UIKit
import RxSwift
import SnapKit
import RxCocoa

// MARK: - TutorialAnimation

enum TutorialAnimation {
    /// 다이얼 외곽을 손가락이 호 경로로 따라가며 회전 제스처를 안내합니다.
    case dialRotation
}

// MARK: - TutorialStep

struct TutorialStep {
    /// 하이라이트할 뷰의 윈도우 좌표 기준 frame.
    /// `someView.convert(someView.bounds, to: nil)` 로 구합니다.
    let targetFrame: CGRect
    let message: String
    var animation: TutorialAnimation? = nil
}

// MARK: - TutorialOverlayViewController

final class TutorialOverlayViewController: UIViewController {

    var steps: [TutorialStep] = []
    var onFinished: (() -> Void)?

    private var currentIndex = 0
    private let disposeBag = DisposeBag()
    private var fingerHintView: UIImageView?

    // MARK: - UI

    private let dimView = UIView()

    private let bubbleContainer: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.background
        v.layer.cornerRadius = 12
        v.layer.shadowColor = UIColor.black.cgColor
        v.layer.shadowOpacity = 0.18
        v.layer.shadowRadius = 10
        v.layer.shadowOffset = CGSize(width: 0, height: 4)
        return v
    }()

    private let messageLabel: UILabel = {
        let l = UILabel()
        l.font = UIFont(name: "GoyangIlsan R", size: 15) ?? .systemFont(ofSize: 15)
        l.textColor = UIColor.accent
        l.numberOfLines = 0
        l.textAlignment = .center
        return l
    }()

    private let arrowImageView: UIImageView = {
        let iv = UIImageView()
        iv.tintColor = UIColor.background
        iv.contentMode = .scaleAspectFit
        return iv
    }()

    private let bottomBar = UIView()

    private lazy var prevButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("< 이전", for: .normal)
        btn.titleLabel?.font = UIFont(name: "GoyangIlsan R", size: 16) ?? .systemFont(ofSize: 16)
        btn.setTitleColor(UIColor.background, for: .normal)
        return btn
    }()

    private lazy var nextButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("다음 >", for: .normal)
        btn.titleLabel?.font = UIFont(name: "GoyangIlsan R", size: 16) ?? .boldSystemFont(ofSize: 16)
        btn.setTitleColor(UIColor.background, for: .normal)
        return btn
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        bindActions()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !steps.isEmpty else { return }
        applyStep(at: 0, animated: false)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = .clear

        dimView.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        view.addSubview(dimView)
        dimView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        view.addSubview(arrowImageView)
        view.addSubview(bubbleContainer)
        bubbleContainer.addSubview(messageLabel)

        messageLabel.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(16)
        }

        // 초기 위치 (applyStep에서 remakeConstraints로 교체됨)
        arrowImageView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview().offset(200)
            make.width.height.equalTo(10)
        }
        bubbleContainer.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(24)
            make.top.equalTo(arrowImageView.snp.bottom)
        }

        view.addSubview(bottomBar)
        bottomBar.addSubview(prevButton)
        bottomBar.addSubview(nextButton)

        bottomBar.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide).inset(8)
            make.height.equalTo(44)
        }
        prevButton.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(24)
            make.centerY.equalToSuperview()
        }
        nextButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(24)
            make.centerY.equalToSuperview()
        }
    }

    private func bindActions() {
        nextButton.rx.tap
            .subscribe(onNext: { [weak self] in
                guard let self else { return }
                if currentIndex < steps.count - 1 {
                    applyStep(at: currentIndex + 1, animated: true)
                } else {
                    finish()
                }
            })
            .disposed(by: disposeBag)

        prevButton.rx.tap
            .subscribe(onNext: { [weak self] in
                guard let self, currentIndex > 0 else { return }
                applyStep(at: currentIndex - 1, animated: true)
            })
            .disposed(by: disposeBag)
    }

    // MARK: - Step

    private func applyStep(at index: Int, animated: Bool) {
        guard index >= 0, index < steps.count else { return }
        currentIndex = index
        let step = steps[index]

        removeFingerHint()
        updateSpotlight(targetFrame: step.targetFrame)
        messageLabel.text = step.message
        repositionCallout(relativeTo: step.targetFrame)
        updateNavigation()

        if animated {
            UIView.animate(withDuration: 0.25) { self.view.layoutIfNeeded() }
        } else {
            view.layoutIfNeeded()
        }

        if case .dialRotation = step.animation {
            startDialRotationHint(in: step.targetFrame)
        }
    }

    // MARK: - Spotlight Mask

    private func updateSpotlight(targetFrame: CGRect) {
        let fullPath = UIBezierPath(rect: dimView.bounds)
        if targetFrame != .zero {
            let hole = UIBezierPath(
                roundedRect: targetFrame.insetBy(dx: -10, dy: -10),
                cornerRadius: 14
            )
            fullPath.append(hole)
            fullPath.usesEvenOddFillRule = true
        }
        let mask = CAShapeLayer()
        mask.path = fullPath.cgPath
        mask.fillRule = .evenOdd
        dimView.layer.mask = mask
    }

    // MARK: - Callout Position

    private func repositionCallout(relativeTo targetFrame: CGRect) {
        let screenMidY = view.bounds.height / 2
        let targetMidY = targetFrame == .zero ? screenMidY - 1 : targetFrame.midY
        let arrowSize: CGFloat = 10
        let gap: CGFloat = 8

        if targetMidY < screenMidY {
            // 타겟이 화면 위쪽 → 말풍선을 타겟 아래에 배치
            let spotlightMaxY = (targetFrame == .zero ? screenMidY : targetFrame.maxY) + 10

            arrowImageView.image = UIImage(systemName: "arrowtriangle.up.fill")
            arrowImageView.snp.remakeConstraints { make in
                make.centerX.equalToSuperview()
                make.top.equalToSuperview().offset(spotlightMaxY + gap)
                make.width.height.equalTo(arrowSize)
            }
            bubbleContainer.snp.remakeConstraints { make in
                make.leading.trailing.equalToSuperview().inset(24)
                make.top.equalTo(arrowImageView.snp.bottom).offset(-2)
            }
        } else {
            // 타겟이 화면 아래쪽 → 말풍선을 타겟 위에 배치
            let spotlightMinY = (targetFrame == .zero ? screenMidY : targetFrame.minY) - 10

            arrowImageView.image = UIImage(systemName: "arrowtriangle.down.fill")
            arrowImageView.snp.remakeConstraints { make in
                make.centerX.equalToSuperview()
                make.bottom.equalToSuperview().inset(view.bounds.height - spotlightMinY + gap)
                make.width.height.equalTo(arrowSize)
            }
            bubbleContainer.snp.remakeConstraints { make in
                make.leading.trailing.equalToSuperview().inset(24)
                make.bottom.equalTo(arrowImageView.snp.top).offset(2)
            }
        }
    }

    // MARK: - Navigation

    private func updateNavigation() {
        prevButton.isHidden = (currentIndex == 0)
        nextButton.setTitle(currentIndex == steps.count - 1 ? "확인" : "다음 >", for: .normal)
    }

    private func finish() {
        removeFingerHint()
        dismiss(animated: true) { [weak self] in
            self?.onFinished?()
        }
    }

    // MARK: - Dial Rotation Hint Animation

    /// 다이얼 외곽 링을 따라 손가락 아이콘이 시계 방향으로 호 이동하는 애니메이션.
    private func startDialRotationHint(in targetFrame: CGRect) {
        removeFingerHint()

        let iv = UIImageView()
        let config = UIImage.SymbolConfiguration(pointSize: 28, weight: .light)
        iv.image = UIImage(systemName: "hand.point.up.left.fill", withConfiguration: config)
        iv.tintColor = UIColor.background.withAlphaComponent(0.9)
        iv.frame = CGRect(x: 0, y: 0, width: 36, height: 36)
        iv.alpha = 0
        view.addSubview(iv)
        fingerHintView = iv

        // TimerDialView 내 dialContainer: cornerRadius = 130 → 지름 260pt
        // targetFrame 은 timerDialView 전체이므로 다이얼이 중앙에 위치
        let dialRadius: CGFloat = min(min(targetFrame.width, targetFrame.height) / 2, 130)
        let center = CGPoint(x: targetFrame.midX, y: targetFrame.midY)

        // 손가락이 터치하는 반지름: 바깥 링(dialContainer)과 내부 face 사이
        let touchRadius = dialRadius * 0.84

        // 호 범위: 10시(-150°) → 2시(-30°), 시계 방향으로 120° 스윕
        let startAngle: CGFloat = -(5 * .pi / 6)   // -150° ≈ 10시
        let endAngle: CGFloat   = -(.pi / 6)        // -30°  ≈  2시

        iv.center = CGPoint(
            x: center.x + touchRadius * cos(startAngle),
            y: center.y + touchRadius * sin(startAngle)
        )

        let arcPath = UIBezierPath(
            arcCenter: center,
            radius: touchRadius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: true
        )

        // 위치 이동 (경로를 따라 이동)
        let posAnim = CAKeyframeAnimation(keyPath: "position")
        posAnim.path = arcPath.cgPath
        posAnim.calculationMode = .paced

        // 투명도: 페이드인 → 유지 → 페이드아웃
        let opacityAnim = CAKeyframeAnimation(keyPath: "opacity")
        opacityAnim.values  = [0.0, 0.9, 0.9, 0.0]
        opacityAnim.keyTimes = [0.0, 0.12, 0.82, 1.0]

        let group = CAAnimationGroup()
        group.animations = [posAnim, opacityAnim]
        group.duration = 1.6
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        iv.layer.add(group, forKey: "dialRotationHint")
    }

    private func removeFingerHint() {
        fingerHintView?.layer.removeAllAnimations()
        fingerHintView?.removeFromSuperview()
        fingerHintView = nil
    }
}
