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

final class QuoteCardEditorViewController: UIViewController {

    private let disposeBag = DisposeBag()
    private let sentence: Sentence
    private let bookTitle: String
    private var highlightLayers: [(view: UIView, layer: CAGradientLayer)] = []

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
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    // MARK: - Setup

    private func setupUI() {
        // dismissButton은 가장 아래 (카드보다 뒤)
        view.addSubview(dismissButton)
        view.addSubview(dimView)
        view.addSubview(cardView)

        cardView.addSubview(backgroundImageView)
        cardView.addSubview(logoImageView)
        cardView.addSubview(sentenceLabel)
        cardView.addSubview(bookTitleLabel)

        view.addSubview(removeLogoButton)
        view.addSubview(backgroundButton)
        view.addSubview(saveButton)
        view.addSubview(removeLogoLabel)
        view.addSubview(backgroundLabel)
        view.addSubview(saveLabel)

        applyFabGlassStyle(to: removeLogoButton, cornerRadius: 26)
        applyFabGlassStyle(to: backgroundButton, cornerRadius: 26)
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
        saveButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(24)
            make.centerY.equalTo(removeLogoButton)
            make.size.equalTo(52)
        }

        // 카드: 버튼 그룹 위 24pt 간격, 좌우 inset 32, 비율 1:1.586
        cardView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(32)
            make.height.equalTo(cardView.snp.width).multipliedBy(1.586)
            make.bottom.equalTo(removeLogoButton.snp.top).offset(-24)
        }

        // 카드 내부
        backgroundImageView.snp.makeConstraints { $0.edges.equalToSuperview() }

        logoImageView.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(17)
            make.top.equalToSuperview().inset(12)
            make.width.equalTo(22)
            make.height.equalTo(26)
        }

        sentenceLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(24)
            make.center.equalToSuperview()
            make.bottom.lessThanOrEqualTo(bookTitleLabel.snp.top).offset(-8)
        }

        bookTitleLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(24)
            make.bottom.equalToSuperview().inset(16)
        }
    }

    // MARK: - Configure

    private func configure() {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.7
        style.alignment = .center
        sentenceLabel.attributedText = NSAttributedString(
            string: sentence.sentence,
            attributes: [
                .font:            UIFont(name: "GowunBatang-Regular", size: 18) ?? .systemFont(ofSize: 18),
                .foregroundColor: UIColor.appPrimary,
                .paragraphStyle:  style,
            ]
        )

        bookTitleLabel.attributedText = NSAttributedString(
            string: bookTitle,
            attributes: [
                .font:            UIFont(name: "GowunBatang-Regular", size: 13) ?? .systemFont(ofSize: 13),
                .foregroundColor: UIColor.appPrimary.withAlphaComponent(0.6),
            ]
        )
    }

    // MARK: - Bindings

    private func bindActions() {
        dismissButton.rx.tap
            .subscribe(onNext: { [weak self] in self?.dismiss(animated: true) })
            .disposed(by: disposeBag)

        // Step 2~5에서 구현 예정
        removeLogoButton.rx.tap
            .subscribe(onNext: { })
            .disposed(by: disposeBag)

        backgroundButton.rx.tap
            .subscribe(onNext: { [weak self] in self?.presentImagePicker() })
            .disposed(by: disposeBag)

        saveButton.rx.tap
            .subscribe(onNext: { })
            .disposed(by: disposeBag)
    }

    // MARK: - FAB Glass Style (BookDetailViewController와 동일한 스펙)

    private func applyFabGlassStyle(to button: UIButton, cornerRadius: CGFloat) {
        guard let superview = button.superview else { return }

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
            DispatchQueue.main.async {
                self.backgroundImageView.image = image
                self.backgroundImageView.isHidden = false
            }
        }
    }
}
