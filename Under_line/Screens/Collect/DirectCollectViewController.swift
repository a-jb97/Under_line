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

    private let disposeBag      = DisposeBag()
    private let bookISBN: String
    private let initialSentence: String?
    private lazy var viewModel  = DirectCollectViewModel(
        bookISBN:   bookISBN,
        repository: AppContainer.shared.sentenceRepository
    )

    var onSaved: (() -> Void)?

    init(bookISBN: String, initialSentence: String? = nil) {
        self.bookISBN        = bookISBN
        self.initialSentence = initialSentence
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    private var selectedEmotion: Emotion?
    private let selectedEmotionRelay = BehaviorRelay<Emotion?>(value: nil)
    private var emotionChips: [NeumorphicChipButton] = []

    // MARK: - Handle

    private let handleView: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.appPrimary.withAlphaComponent(0.25)
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
        v.layer.borderColor = UIColor.appPrimary.cgColor
        v.clipsToBounds = true
        return v
    }()

    private lazy var sentenceTextView: UITextView = {
        let tv = UITextView()
        tv.backgroundColor = .clear
        tv.font = UIFont(name: "GoyangIlsan R", size: 14) ?? .systemFont(ofSize: 14)
        tv.textColor = UIColor.appPrimary
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.delegate = self
        return tv
    }()

    private let sentencePlaceholder: UILabel = {
        let l = UILabel()
        l.text = "수집할 밑줄을 입력하세요"
        l.font = UIFont(name: "GoyangIlsan R", size: 14) ?? .systemFont(ofSize: 14)
        l.textColor = UIColor.appPrimary.withAlphaComponent(0.4)
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
        v.layer.borderColor = UIColor.appPrimary.cgColor
        return v
    }()

    private let pageTextField: UITextField = {
        let tf = UITextField()
        tf.backgroundColor = .clear
        tf.font = UIFont(name: "GoyangIlsan R", size: 14) ?? .systemFont(ofSize: 14)
        tf.textColor = UIColor.appPrimary
        tf.keyboardType = .numberPad
        tf.attributedPlaceholder = NSAttributedString(
            string: "예: 42",
            attributes: [
                .font: UIFont(name: "GoyangIlsan R", size: 14) ?? UIFont.systemFont(ofSize: 14),
                .foregroundColor: UIColor.appPrimary.withAlphaComponent(0.4),
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
        v.layer.borderColor = UIColor.appPrimary.cgColor
        v.clipsToBounds = true
        return v
    }()

    private lazy var memoTextView: UITextView = {
        let tv = UITextView()
        tv.backgroundColor = .clear
        tv.font = UIFont(name: "GoyangIlsan R", size: 14) ?? .systemFont(ofSize: 14)
        tv.textColor = UIColor.appPrimary
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.delegate = self
        return tv
    }()

    private let memoPlaceholder: UILabel = {
        let l = UILabel()
        l.text = "이 밑줄에 대한 나의 생각..."
        l.font = UIFont(name: "GoyangIlsan R", size: 14) ?? .systemFont(ofSize: 14)
        l.textColor = UIColor.appPrimary.withAlphaComponent(0.4)
        l.numberOfLines = 0
        l.isUserInteractionEnabled = false
        return l
    }()

    // MARK: - Register Button

    private let registerButton: UIButton = {
        let btn = UIButton(type: .custom)
        btn.setTitle("추가하기", for: .normal)
        btn.titleLabel?.font = UIFont(name: "GowunBatang-Bold", size: 18)
            ?? .boldSystemFont(ofSize: 18)
        btn.setTitleColor(UIColor.background, for: .normal)
        btn.backgroundColor = UIColor.walnut
        btn.layer.cornerRadius = 12
        return btn
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.background
        configureSheet()
        setupUI()
        setupConstraints()
        bindActions()
        setupKeyboardHandling()

        if let text = initialSentence, !text.isEmpty {
            sentenceTextView.text    = text
            sentencePlaceholder.isHidden = true
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Keyboard

    private func setupKeyboardHandling() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    private var keyboardHeight: CGFloat = 0
    private weak var activeTextView: UITextView?

    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let info = notification.userInfo,
              let keyboardFrame = info[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = info[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval
        else { return }

        keyboardHeight = keyboardFrame.height - view.safeAreaInsets.bottom
        scrollView.contentInset.bottom = keyboardHeight
        scrollView.verticalScrollIndicatorInsets.bottom = keyboardHeight

        guard let active = activeTextView, active === memoTextView else { return }
        UIView.animate(withDuration: duration) {
            self.scrollToActive(active, animated: false)
        }
    }

    private func scrollToActive(_ active: UIView, animated: Bool) {
        let activeRect = active.convert(active.bounds, to: scrollView)
        let buttonRect = registerButton.convert(registerButton.bounds, to: scrollView)
        let rect = activeRect.union(buttonRect).insetBy(dx: 0, dy: -16)
        scrollView.scrollRectToVisible(rect, animated: animated)
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        guard let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval
        else { return }
        keyboardHeight = 0
        UIView.animate(withDuration: duration) {
            self.scrollView.contentInset.bottom = 0
            self.scrollView.verticalScrollIndicatorInsets.bottom = 0
        }
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
        let output = viewModel.transform(input: DirectCollectViewModel.Input(
            sentence: sentenceTextView.rx.text.orEmpty.asObservable(),
            page:     pageTextField.rx.text.orEmpty.asObservable(),
            emotion:  selectedEmotionRelay.asObservable(),
            memo:     memoTextView.rx.text.orEmpty.asObservable(),
            saveTap:  registerButton.rx.tap.asObservable()
        ))

        output.isFormValid
            .drive(registerButton.rx.isEnabled)
            .disposed(by: disposeBag)

        output.isFormValid
            .map { $0 ? 1.0 as CGFloat : 0.4 }
            .drive(registerButton.rx.alpha)
            .disposed(by: disposeBag)

        output.saveCompleted
            .emit(onNext: { [weak self] in
                guard let self else { return }
                let onSaved = self.onSaved
                self.dismiss(animated: true) { onSaved?() }
            })
            .disposed(by: disposeBag)

        pageTextField.rx.controlEvent(.editingDidBegin)
            .subscribe(onNext: { [weak self] in self?.activeTextView = nil })
            .disposed(by: disposeBag)

        let chipTaps = zip(Emotion.allCases, emotionChips).map { (emotion, chip) in
            chip.rx.controlEvent(.touchUpInside).map { emotion }
        }
        Observable.merge(chipTaps)
            .subscribe(onNext: { [weak self] emotion in
                guard let self else { return }
                let tappingSelected = self.selectedEmotion == emotion
                self.selectedEmotion = tappingSelected ? nil : emotion
                self.selectedEmotionRelay.accept(self.selectedEmotion)
                self.emotionChips.forEach { chip in
                    chip.isSelected = !tappingSelected && chip.emotion == emotion
                }
            })
            .disposed(by: disposeBag)
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
    func textViewDidBeginEditing(_ textView: UITextView) {
        activeTextView = textView
        guard textView === memoTextView, keyboardHeight > 0 else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.activeTextView === textView else { return }
            self.scrollToActive(textView, animated: true)
        }
    }

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

    let emotion: Emotion

    // MARK: Selection — update shadow direction on change

    override var isSelected: Bool {
        didSet { guard oldValue != isSelected else { return }; updateAppearance() }
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
