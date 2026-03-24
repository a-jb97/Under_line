//
//  DirectCollectViewController.swift
//  Under_line
//
//  수동 문장 수집 바텀 시트 (Node ukBq1)
//  CameraCollectionViewController의 directCollectButton 탭 →
//  CameraVC dismiss → BookDetailVC에서 pageSheet로 present
//

import UIKit
import SnapKit
import RxSwift
import RxCocoa

final class DirectCollectViewController: UIViewController {

    private let disposeBag = DisposeBag()

    // MARK: - Emotion

    enum Emotion: Int, CaseIterable {
        case joy, calm, sad, touched, pensive, tense

        var emoji: UIImage {
            switch self {
            case .joy:     return .happy
            case .calm:    return .calm
            case .sad:     return .sad
            case .touched: return .moved
            case .pensive: return .meditation
            case .tense:   return .nervous
            }
        }

        var label: String {
            switch self {
            case .joy:     return "기쁨"
            case .calm:    return "평온"
            case .sad:     return "슬픔"
            case .touched: return "감동"
            case .pensive: return "사색"
            case .tense:   return "긴장"
            }
        }
    }

    private var selectedEmotion: Emotion?
    private var emotionChips: [NeumorphicChipButton] = []

    // MARK: - Handle

    private let handleView: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.primary.withAlphaComponent(0.25)
        v.layer.cornerRadius = 2.5
        v.isUserInteractionEnabled = false
        return v
    }()

    // MARK: - Header

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.text = "밑줄 수집"
        l.font = UIFont(name: "GowunBatang-Bold", size: 22)
            ?? .systemFont(ofSize: 22, weight: .bold)
        l.textColor = UIColor.accent
        return l
    }()

    // MARK: - Scroll

    private let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.showsVerticalScrollIndicator = false
        sv.keyboardDismissMode = .onDrag
        sv.alwaysBounceVertical = true
        return sv
    }()

    private let formStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.spacing = 20
        return sv
    }()

    // MARK: - Sentence Field

    private let sentenceLabel = DirectCollectViewController.fieldLabel("밑줄 내용 *")

    private let sentenceBox: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 10
        v.layer.borderWidth = 1
        v.layer.borderColor = UIColor.primary.cgColor
        v.clipsToBounds = true
        return v
    }()

    private lazy var sentenceTextView: UITextView = {
        let tv = UITextView()
        tv.backgroundColor = .clear
        tv.font = UIFont(name: "GoyangIlsan R", size: 14) ?? .systemFont(ofSize: 14)
        tv.textColor = UIColor.primary
        tv.delegate = self
        return tv
    }()

    private let sentencePlaceholder: UILabel = {
        let l = UILabel()
        l.text = "수집할 밑줄을 입력하세요"
        l.font = UIFont(name: "GoyangIlsan R", size: 14) ?? .systemFont(ofSize: 14)
        l.textColor = UIColor.primary.withAlphaComponent(0.4)
        l.numberOfLines = 0
        l.isUserInteractionEnabled = false
        return l
    }()

    // MARK: - Page Field

    private let pageLabel = DirectCollectViewController.fieldLabel("페이지 번호 *")

    private let pageBox: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 10
        v.layer.borderWidth = 1
        v.layer.borderColor = UIColor.primary.cgColor
        return v
    }()

    private let pageTextField: UITextField = {
        let tf = UITextField()
        tf.backgroundColor = .clear
        tf.font = UIFont(name: "GoyangIlsan R", size: 14) ?? .systemFont(ofSize: 14)
        tf.textColor = UIColor.primary
        tf.keyboardType = .numberPad
        tf.attributedPlaceholder = NSAttributedString(
            string: "예: 42",
            attributes: [
                .font: UIFont(name: "GoyangIlsan R", size: 14) ?? UIFont.systemFont(ofSize: 14),
                .foregroundColor: UIColor.primary.withAlphaComponent(0.4),
            ]
        )
        return tf
    }()

    // MARK: - Emotion Field

    private let emotionLabel = DirectCollectViewController.fieldLabel("감정 *")

    private let emotionHintLabel: UILabel = {
        let l = UILabel()
        l.text = "문장을 읽을 때 느꼈던 감정을 선택해주세요"
        l.font = UIFont(name: "GoyangIlsan R", size: 11) ?? .systemFont(ofSize: 11)
        l.textColor = UIColor.accent.withAlphaComponent(0.6)
        l.numberOfLines = 0
        return l
    }()

    private let emotionChipsRow: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.distribution = .fillEqually
        sv.spacing = 8
        return sv
    }()

    // MARK: - Memo Field

    private let memoLabel = DirectCollectViewController.fieldLabel("메모")

    private let memoBox: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 10
        v.layer.borderWidth = 1
        v.layer.borderColor = UIColor.primary.cgColor
        v.clipsToBounds = true
        return v
    }()

    private lazy var memoTextView: UITextView = {
        let tv = UITextView()
        tv.backgroundColor = .clear
        tv.font = UIFont(name: "GoyangIlsan R", size: 14) ?? .systemFont(ofSize: 14)
        tv.textColor = UIColor.primary
        tv.delegate = self
        return tv
    }()

    private let memoPlaceholder: UILabel = {
        let l = UILabel()
        l.text = "이 밑줄에 대한 나의 생각..."
        l.font = UIFont(name: "GoyangIlsan R", size: 14) ?? .systemFont(ofSize: 14)
        l.textColor = UIColor.primary.withAlphaComponent(0.4)
        l.numberOfLines = 0
        l.isUserInteractionEnabled = false
        return l
    }()

    // MARK: - Register Button

    private let registerButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.attributedTitle = AttributedString(
            "추가하기",
            attributes: AttributeContainer([
                .font: UIFont(name: "GowunBatang-Bold", size: 18)
                    ?? UIFont.systemFont(ofSize: 18, weight: .bold),
            ])
        )
        config.baseForegroundColor = UIColor.background
        config.baseBackgroundColor = UIColor.primary
        config.background.cornerRadius = 12
        return UIButton(configuration: config)
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
        sheet.detents = [.large()]
        sheet.prefersGrabberVisible = false
        sheet.preferredCornerRadius = 24
    }

    // MARK: - Setup

    private func setupUI() {
        view.addSubview(handleView)
        view.addSubview(titleLabel)
        view.addSubview(scrollView)
        scrollView.addSubview(formStack)

        // Sentence
        sentenceBox.addSubview(sentenceTextView)
        sentenceBox.addSubview(sentencePlaceholder)
        formStack.addArrangedSubview(vstack([sentenceLabel, sentenceBox], spacing: 8))

        // Page
        pageBox.addSubview(pageTextField)
        formStack.addArrangedSubview(vstack([pageLabel, pageBox], spacing: 8))

        // Emotion
        for emotion in Emotion.allCases {
            let chip = NeumorphicChipButton(emotion: emotion)
            chip.tag = emotion.rawValue
            chip.addTarget(self, action: #selector(chipTapped(_:)), for: .touchUpInside)
            emotionChipsRow.addArrangedSubview(chip)
            emotionChips.append(chip)
        }
        let emotionHeaderStack = vstack([emotionLabel, emotionHintLabel], spacing: 8)
        formStack.addArrangedSubview(vstack([emotionHeaderStack, emotionChipsRow], spacing: 16))

        // Memo
        memoBox.addSubview(memoTextView)
        memoBox.addSubview(memoPlaceholder)
        formStack.addArrangedSubview(vstack([memoLabel, memoBox], spacing: 8))

        // Register
        formStack.addArrangedSubview(registerButton)
    }

    private func vstack(_ views: [UIView], spacing: CGFloat) -> UIStackView {
        let sv = UIStackView(arrangedSubviews: views)
        sv.axis = .vertical
        sv.spacing = spacing
        return sv
    }

    private func setupConstraints() {
        handleView.snp.makeConstraints { make in
            make.top.equalToSuperview().inset(12)
            make.centerX.equalToSuperview()
            make.width.equalTo(36)
            make.height.equalTo(5)
        }

        titleLabel.snp.makeConstraints { make in
            make.top.equalTo(handleView.snp.bottom).offset(11)
            make.leading.equalToSuperview().inset(24)
            make.height.equalTo(52)
        }

        scrollView.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom)
            make.leading.trailing.bottom.equalToSuperview()
        }

        formStack.snp.makeConstraints { make in
            make.top.equalToSuperview().inset(5)
            make.leading.trailing.equalToSuperview().inset(24)
            make.bottom.equalToSuperview().inset(24)
            make.width.equalTo(scrollView).offset(-48)
        }

        sentenceBox.snp.makeConstraints { make in make.height.equalTo(160) }
        sentenceTextView.snp.makeConstraints { make in make.edges.equalToSuperview().inset(16) }
        sentencePlaceholder.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview().inset(16)
        }

        pageBox.snp.makeConstraints { make in make.height.equalTo(48) }
        pageTextField.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.leading.trailing.equalToSuperview().inset(16)
        }

        emotionChipsRow.snp.makeConstraints { make in make.height.equalTo(64) }

        memoBox.snp.makeConstraints { make in make.height.equalTo(120) }
        memoTextView.snp.makeConstraints { make in make.edges.equalToSuperview().inset(16) }
        memoPlaceholder.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview().inset(16)
        }

        registerButton.snp.makeConstraints { make in make.height.equalTo(52) }
    }

    // MARK: - Bindings

    private func bindActions() {
        registerButton.rx.tap
            .subscribe(onNext: { [weak self] in
                // TODO: 문장 저장
                print("추가하기 탭")
                self?.dismiss(animated: true)
            })
            .disposed(by: disposeBag)
    }

    // MARK: - Chip Selection

    @objc private func chipTapped(_ sender: UIControl) {
        guard let emotion = Emotion(rawValue: sender.tag) else { return }
        let tappingSelected = selectedEmotion == emotion
        selectedEmotion = tappingSelected ? nil : emotion
        emotionChips.forEach { chip in
            chip.isSelected = !tappingSelected && chip.tag == emotion.rawValue
        }
    }

    // MARK: - Helpers

    private static func fieldLabel(_ text: String) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = UIFont(name: "GoyangIlsan R", size: 14) ?? .systemFont(ofSize: 14, weight: .semibold)
        l.textColor = UIColor.accent
        return l
    }
}

// MARK: - UITextViewDelegate

extension DirectCollectViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        if textView === sentenceTextView {
            sentencePlaceholder.isHidden = !textView.text.isEmpty
        } else if textView === memoTextView {
            memoPlaceholder.isHidden = !textView.text.isEmpty
        }
    }
}

// MARK: - NeumorphicChipButton

private final class NeumorphicChipButton: UIControl {

    // MARK: Neumorphic shadow colors
    private static let shadowDark  = UIColor(hex: "#c8b2af").cgColor
    private static let shadowLight = UIColor(white: 1, alpha: 0.8).cgColor

    private var darkLayer  = CALayer()
    private var lightLayer = CALayer()

    // MARK: Selection — update shadow direction on change

    override var isSelected: Bool {
        didSet { guard oldValue != isSelected else { return }; updateAppearance() }
    }

    init(emotion: DirectCollectViewController.Emotion) {
        super.init(frame: .zero)
        backgroundColor = UIColor.background
        layer.cornerRadius = 16
        setupShadowLayers()
        setupContent(emotion: emotion)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Layers

    private func setupShadowLayers() {
        // Dark shadow (bottom-right when unselected, top-left when selected)
        darkLayer.cornerRadius = 16
        darkLayer.backgroundColor = UIColor.background.cgColor
        darkLayer.shadowColor = NeumorphicChipButton.shadowDark
        darkLayer.shadowOpacity = 1.0
        darkLayer.shadowRadius  = 5
        darkLayer.shadowOffset  = CGSize(width: 3, height: 3)
        layer.insertSublayer(darkLayer, at: 0)

        // Light shadow (top-left when unselected, bottom-right when selected)
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

    // MARK: Content

    private func setupContent(emotion: DirectCollectViewController.Emotion) {
        let emojiImageView = UIImageView(image: emotion.emoji)
        emojiImageView.contentMode = .scaleAspectFit
        emojiImageView.isUserInteractionEnabled = false
        emojiImageView.snp.makeConstraints { make in make.size.equalTo(28) }

        let nameLabel = UILabel()
        nameLabel.text = emotion.label
        nameLabel.font = UIFont(name: "GoyangIlsan R", size: 10) ?? .systemFont(ofSize: 10)
        nameLabel.textColor = UIColor.primary
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
