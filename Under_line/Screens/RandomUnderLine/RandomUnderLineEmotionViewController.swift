//
//  RandomUnderLineEmotionViewController.swift
//  Under_line
//
//  앱 실행 시 표시되는 감정 선택 모달 (pageSheet)
//  DirectCollectViewController의 Emotion Field와 동일한 디자인
//

import UIKit
import SnapKit
import RxSwift
import RxCocoa

final class RandomUnderLineEmotionViewController: UIViewController {

    private let disposeBag       = DisposeBag()
    private let enabledEmotions: [Emotion]
    private let onEmotionSelected: (Emotion) -> Void

    private var emotionChips: [NeumorphicChipButton] = []

    init(enabledEmotions: [Emotion], onEmotionSelected: @escaping (Emotion) -> Void) {
        self.enabledEmotions   = enabledEmotions
        self.onEmotionSelected = onEmotionSelected
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Title

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.text = "지금 어떤 감정이 느껴지시나요?"
        l.font = UIFont(name: "GowunBatang-Bold", size: 18)
            ?? .systemFont(ofSize: 18, weight: .bold)
        l.textColor = UIColor.accent
        l.numberOfLines = 0
        return l
    }()

    // MARK: - Chips Row

    private let emotionChipsRow: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.distribution = .fillEqually
        sv.spacing = 8
        return sv
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.background
        configureSheet()
        setupUI()
        setupConstraints()
        bindActions()
    }

    // MARK: - Sheet

    private func configureSheet() {
        guard let sheet = sheetPresentationController else { return }
        let customDetent = UISheetPresentationController.Detent.custom(
            identifier: .init("emotionPicker")
        ) { _ in 200 }
        sheet.detents = [customDetent]
        sheet.prefersGrabberVisible = false
        sheet.preferredCornerRadius = 52
        sheet.prefersScrollingExpandsWhenScrolledToEdge = false
    }

    // MARK: - Setup

    private func setupUI() {
        view.addSubview(titleLabel)

        for emotion in Emotion.allCases {
            let chip = NeumorphicChipButton(emotion: emotion)
            chip.isEnabled = enabledEmotions.contains(emotion)
            emotionChipsRow.addArrangedSubview(chip)
            emotionChips.append(chip)
        }
        view.addSubview(emotionChipsRow)
    }

    private func setupConstraints() {
        titleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(44)
            make.leading.trailing.equalToSuperview().inset(24)
        }

        emotionChipsRow.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.leading.trailing.equalToSuperview().inset(16)
            make.height.equalTo(64)
        }
    }

    // MARK: - Bindings

    private func bindActions() {
        let chipTaps = zip(Emotion.allCases, emotionChips).map { (emotion, chip) in
            chip.rx.controlEvent(.touchUpInside).map { emotion }
        }
        Observable.merge(chipTaps)
            .subscribe(onNext: { [weak self] emotion in
                guard let self else { return }
                let callback = self.onEmotionSelected
                self.dismiss(animated: true) { callback(emotion) }
            })
            .disposed(by: disposeBag)
    }
}

// MARK: - NeumorphicChipButton

private final class NeumorphicChipButton: UIControl {

    private static let shadowDark  = UIColor(hex: "#c8b2af").cgColor
    private static let shadowLight = UIColor(white: 1, alpha: 0.8).cgColor

    private var darkLayer  = CALayer()
    private var lightLayer = CALayer()

    let emotion: Emotion

    override var isSelected: Bool {
        didSet { guard oldValue != isSelected else { return }; updateAppearance() }
    }

    override var isEnabled: Bool {
        didSet { alpha = isEnabled ? 1.0 : 0.35 }
    }

    init(emotion: Emotion) {
        self.emotion = emotion
        super.init(frame: .zero)
        backgroundColor = UIColor.background
        layer.cornerRadius = 16
        setupShadowLayers()
        setupContent(emotion: emotion)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupShadowLayers() {
        darkLayer.cornerRadius = 16
        darkLayer.backgroundColor = UIColor.background.cgColor
        darkLayer.shadowColor = NeumorphicChipButton.shadowDark
        darkLayer.shadowOpacity = 1.0
        darkLayer.shadowRadius  = 5
        darkLayer.shadowOffset  = CGSize(width: 3, height: 3)
        layer.insertSublayer(darkLayer, at: 0)

        lightLayer.cornerRadius = 16
        lightLayer.backgroundColor = UIColor.background.cgColor
        lightLayer.shadowColor = NeumorphicChipButton.shadowLight
        lightLayer.shadowOpacity = 0.8
        lightLayer.shadowRadius  = 5
        lightLayer.shadowOffset  = CGSize(width: -3, height: -3)
        layer.insertSublayer(lightLayer, at: 0)
    }

    private func updateAppearance() {
        let darkOffset  = isSelected ? CGSize(width: -3, height: -3) : CGSize(width:  3, height:  3)
        let lightOffset = isSelected ? CGSize(width:  3, height:  3) : CGSize(width: -3, height: -3)
        darkLayer.shadowOffset  = darkOffset
        lightLayer.shadowOffset = lightOffset
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        darkLayer.frame  = bounds
        lightLayer.frame = bounds
    }

    private func setupContent(emotion: Emotion) {
        let emojiImageView = UIImageView(image: emotion.emoji)
        emojiImageView.contentMode = .scaleAspectFit
        emojiImageView.isUserInteractionEnabled = false
        emojiImageView.snp.makeConstraints { make in make.size.equalTo(28) }

        let nameLabel = UILabel()
        nameLabel.text = emotion.label
        nameLabel.font = UIFont(name: "GoyangIlsan R", size: 10) ?? .systemFont(ofSize: 10)
        nameLabel.textColor = UIColor.appPrimary
        nameLabel.textAlignment = .center
        nameLabel.isUserInteractionEnabled = false

        let stack = UIStackView(arrangedSubviews: [emojiImageView, nameLabel])
        stack.axis = .vertical
        stack.spacing = 4
        stack.alignment = .center
        stack.isUserInteractionEnabled = false

        addSubview(stack)
        stack.snp.makeConstraints { make in make.center.equalToSuperview() }
    }
}
