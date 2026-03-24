//
//  BookDetailViewController.swift
//  Under_line
//
//  책 탭 시 push되는 상세 화면 — 나의 밑줄 (Node 9mut1)
//

import UIKit
import SnapKit
import RxSwift
import RxCocoa

final class BookDetailViewController: UIViewController {

    private let disposeBag = DisposeBag()
    private var highlightLayers: [(view: UIView, layer: CAGradientLayer)] = []

    // MARK: - UI Components

    // Header
    private lazy var backButton: UIButton = {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        btn.setImage(UIImage(systemName: "chevron.left", withConfiguration: cfg), for: .normal)
        btn.tintColor = UIColor.accent
        return btn
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.text = "나의 밑줄"
        l.font = UIFont(name: "GowunBatang-Bold", size: 34)
            ?? .systemFont(ofSize: 34, weight: .bold)
        l.textColor = UIColor.accent
        return l
    }()

    private lazy var timerButton: UIButton = {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        btn.setImage(UIImage(systemName: "timer", withConfiguration: cfg), for: .normal)
        btn.tintColor = UIColor.primary
        btn.layer.cornerRadius = 20
        btn.clipsToBounds = true
        return btn
    }()

    // Quote Card
    private let quoteCard: UIView = {
        let v = UIView()
        v.backgroundColor = .white
        v.layer.cornerRadius = 16
        v.layer.shadowColor   = UIColor.black.cgColor
        v.layer.shadowOpacity = Float(CGFloat(0x26) / 255)
        v.layer.shadowRadius  = 12
        v.layer.shadowOffset  = CGSize(width: 0, height: 8)
        return v
    }()

    private let quoteTextLabel: UILabel = {
        let l = UILabel()
        l.numberOfLines = 0
        l.textAlignment = .center
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.2
        style.alignment = .center
        l.attributedText = NSAttributedString(
            string: "사람은 무엇으로 사는가. 사랑이다. \n사람은 사랑 없이는 살 수 없다.",
            attributes: [
                .font:            UIFont(name: "GowunBatang-Regular", size: 18) ?? .systemFont(ofSize: 18),
                .foregroundColor: UIColor.primary,
                .paragraphStyle:  style,
            ]
        )
        return l
    }()

    private let pageNumLabel: UILabel = {
        let l = UILabel()
        l.text = "p.42"
        l.font = UIFont(name: "GoyangIlsan R", size: 13)
            ?? .systemFont(ofSize: 13)
        l.textColor = UIColor.primary.withAlphaComponent(0.5)
        l.textAlignment = .right
        return l
    }()

    // Page Dots
    private lazy var dot1: UIView = makeDot(alpha: 1.0)
    private lazy var dot2: UIView = makeDot(alpha: 0.3)
    private lazy var dot3: UIView = makeDot(alpha: 0.3)

    private lazy var pageDotsStack: UIStackView = {
        let sv = UIStackView(arrangedSubviews: [dot1, dot2, dot3])
        sv.axis      = .horizontal
        sv.spacing   = 8
        sv.alignment = .center
        return sv
    }()

    // Book Info Section (neumorphic)
    private let bookInfoSection: UIView = {
        let v = UIView()
        v.backgroundColor   = UIColor.background
        v.layer.cornerRadius = 16
        v.layer.shadowColor   = UIColor(hex: "#5d4037").cgColor
        v.layer.shadowOpacity = Float(CGFloat(0x30) / 255)
        v.layer.shadowRadius  = 4
        v.layer.shadowOffset  = CGSize(width: 4, height: 4)
        return v
    }()

    private let bookCoverView: UIView = {
        let v = UIView()
        v.backgroundColor   = UIColor.primary
        v.layer.cornerRadius = 6
        return v
    }()

    private let bookTitleLabel: UILabel = {
        let l = UILabel()
        l.text      = "사랑의 기술"
        l.font      = UIFont(name: "GowunBatang-Bold", size: 17)
            ?? .systemFont(ofSize: 17, weight: .bold)
        l.textColor = UIColor.accent
        return l
    }()

    private let bookAuthorLabel: UILabel = {
        let l = UILabel()
        l.text      = "에리히 프롬"
        l.font      = UIFont(name: "GowunBatang-Regular", size: 13)
            ?? .systemFont(ofSize: 13)
        l.textColor = UIColor.primary
        return l
    }()

    private let publisherLabel: UILabel = {
        let l = UILabel()
        l.text      = "문예출판사 · 2023"
        l.font      = UIFont(name: "GoyangIlsan R", size: 11)
            ?? .systemFont(ofSize: 11)
        l.textColor = UIColor.primary.withAlphaComponent(0.5)
        return l
    }()

    private let genreTagView: UIView = {
        let v = UIView()
        v.backgroundColor   = UIColor.primary.withAlphaComponent(0.7)
        v.layer.cornerRadius = 3
        return v
    }()

    private let genreTagLabel: UILabel = {
        let l = UILabel()
        l.text      = "철학/심리학"
        l.font      = UIFont(name: "GoyangIlsan R", size: 10)
            ?? .systemFont(ofSize: 10)
        l.textColor = .white
        return l
    }()

    private lazy var moreButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("더 보기", for: .normal)
        btn.titleLabel?.font = UIFont(name: "GoyangIlsan R", size: 11)
            ?? .systemFont(ofSize: 11)
        btn.setTitleColor(UIColor.primary.withAlphaComponent(0.7), for: .normal)
        btn.contentHorizontalAlignment = .right
        return btn
    }()

    // Progress Section (neumorphic inner card)
    private let progressSection: UIView = {
        let v = UIView()
        v.backgroundColor   = UIColor.background
        v.layer.cornerRadius = 12
        v.layer.shadowColor   = UIColor(hex: "#5d4037").cgColor
        v.layer.shadowOpacity = Float(CGFloat(0x25) / 255)
        v.layer.shadowRadius  = 2.5
        v.layer.shadowOffset  = CGSize(width: 3, height: 3)
        return v
    }()

    private let progressHeaderLabel: UILabel = {
        let l = UILabel()
        let attrStr = NSMutableAttributedString(
            string: "독서 진행률 : ",
            attributes: [
                .font:            UIFont(name: "GoyangIlsan R", size: 13) ?? .systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: UIColor.accent,
            ]
        )
        attrStr.append(NSAttributedString(
            string: "68%",
            attributes: [
                .font:            UIFont(name: "GoyangIlsan R", size: 13) ?? .systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: UIColor.primary,
            ]
        ))
        l.attributedText = attrStr
        return l
    }()

    private lazy var editButton: UIButton = {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 10, weight: .regular)
        btn.setImage(UIImage(systemName: "pencil", withConfiguration: cfg), for: .normal)
        btn.setTitle(" 편집", for: .normal)
        btn.titleLabel?.font = UIFont(name: "GoyangIlsan R", size: 12)
            ?? .systemFont(ofSize: 12, weight: .semibold)
        btn.tintColor = UIColor.primary.withAlphaComponent(0.7)
        btn.setTitleColor(UIColor.primary.withAlphaComponent(0.7), for: .normal)
        return btn
    }()

    private let progressBarBg: UIView = {
        let v = UIView()
        v.backgroundColor   = UIColor(hex: "#5d4037", alpha: CGFloat(0x20) / 255)
        v.layer.cornerRadius = 6
        v.clipsToBounds      = true
        return v
    }()

    private let progressBarFill: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 4
        v.clipsToBounds      = true
        return v
    }()

    private let progressDetailLabel: UILabel = {
        let l = UILabel()
        l.text      = "187 / 276 페이지"
        l.font      = UIFont(name: "GoyangIlsan R", size: 11)
            ?? .systemFont(ofSize: 11)
        l.textColor = UIColor.primary.withAlphaComponent(0.45)
        return l
    }()

    // FAB
    private lazy var fabButton: UIButton = {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        btn.setImage(UIImage(systemName: "plus", withConfiguration: cfg), for: .normal)
        btn.tintColor = UIColor.walnut
        btn.layer.cornerRadius = 26
        btn.clipsToBounds = true
        return btn
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupConstraints()
        setupProgressGradient()
        bindActions()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.interactivePopGestureRecognizer?.delegate = nil
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        for (view, gradient) in highlightLayers {
            gradient.frame = view.bounds
        }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = UIColor.background

        // Header
        view.addSubview(backButton)
        view.addSubview(titleLabel)
        view.addSubview(timerButton)

        // Quote Card
        quoteCard.addSubview(quoteTextLabel)
        quoteCard.addSubview(pageNumLabel)
        view.addSubview(quoteCard)
        view.addSubview(pageDotsStack)

        // Book Info Section
        genreTagView.addSubview(genreTagLabel)
        bookInfoSection.addSubview(bookCoverView)
        bookInfoSection.addSubview(bookTitleLabel)
        bookInfoSection.addSubview(bookAuthorLabel)
        bookInfoSection.addSubview(publisherLabel)
        bookInfoSection.addSubview(genreTagView)
        bookInfoSection.addSubview(moreButton)

        progressBarBg.addSubview(progressBarFill)
        progressSection.addSubview(progressHeaderLabel)
        progressSection.addSubview(editButton)
        progressSection.addSubview(progressBarBg)
        progressSection.addSubview(progressDetailLabel)

        bookInfoSection.addSubview(progressSection)
        view.addSubview(bookInfoSection)

        // FAB
        view.addSubview(fabButton)

        applyFabGlassStyle(to: timerButton, cornerRadius: 20)
        applyFabGlassStyle(to: fabButton,   cornerRadius: 26)
    }

    private func setupConstraints() {
        // Header (design: 헤더 높이 ≈ 62, top = safeArea)
        backButton.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(24)
            make.top.equalTo(view.safeAreaLayoutGuide).offset(17)
            make.size.equalTo(28)
        }

        titleLabel.snp.makeConstraints { make in
            make.leading.equalTo(backButton.snp.trailing).offset(4)
            make.centerY.equalTo(backButton)
        }

        timerButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(24)
            make.centerY.equalTo(backButton)
            make.size.equalTo(40)
        }

        // Quote Card (height: 266, padding: [24,24,20,24])
        quoteCard.snp.makeConstraints { make in
            make.top.equalTo(backButton.snp.bottom).offset(32)
            make.leading.trailing.equalToSuperview().inset(24)
            make.height.equalTo(266)
        }

        quoteTextLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(24)
            make.center.equalToSuperview()
        }

        pageNumLabel.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(24)
            make.bottom.equalToSuperview().inset(20)
        }

        // Page Dots (gap: 8)
        pageDotsStack.snp.makeConstraints { make in
            make.top.equalTo(quoteCard.snp.bottom).offset(16)
            make.centerX.equalToSuperview()
        }

        dot1.snp.makeConstraints { make in make.size.equalTo(7) }
        dot2.snp.makeConstraints { make in make.size.equalTo(7) }
        dot3.snp.makeConstraints { make in make.size.equalTo(7) }

        // Book Info Section (cornerRadius 16, padding 16, gap 20)
        bookInfoSection.snp.makeConstraints { make in
            make.top.equalTo(pageDotsStack.snp.bottom).offset(24)
            make.leading.trailing.equalToSuperview().inset(24)
        }

        // Book Cover (60×83)
        bookCoverView.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(16)
            make.top.equalToSuperview().inset(16)
            make.width.equalTo(60)
            make.height.equalTo(83)
        }

        // Book Title
        bookTitleLabel.snp.makeConstraints { make in
            make.leading.equalTo(bookCoverView.snp.trailing).offset(14)
            make.trailing.equalToSuperview().inset(16)
            make.top.equalTo(bookCoverView)
        }

        bookAuthorLabel.snp.makeConstraints { make in
            make.leading.trailing.equalTo(bookTitleLabel)
            make.top.equalTo(bookTitleLabel.snp.bottom).offset(4)
        }

        publisherLabel.snp.makeConstraints { make in
            make.leading.trailing.equalTo(bookTitleLabel)
            make.top.equalTo(bookAuthorLabel.snp.bottom).offset(4)
        }

        genreTagView.snp.makeConstraints { make in
            make.leading.equalTo(bookTitleLabel)
            make.top.equalTo(publisherLabel.snp.bottom).offset(6)
            make.bottom.lessThanOrEqualTo(bookCoverView.snp.bottom)
        }

        genreTagLabel.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 2, left: 8, bottom: 2, right: 8))
        }

        moreButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(16)
            make.centerY.equalTo(genreTagView)
        }

        // Progress Section (cornerRadius 12, padding [12,14])
        progressSection.snp.makeConstraints { make in
            make.top.equalTo(bookCoverView.snp.bottom).offset(20)
            make.leading.trailing.equalToSuperview().inset(16)
            make.bottom.equalToSuperview().inset(16)
        }

        progressHeaderLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(14)
            make.top.equalToSuperview().inset(12)
        }

        editButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(14)
            make.centerY.equalTo(progressHeaderLabel)
        }

        progressBarBg.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(14)
            make.top.equalTo(progressHeaderLabel.snp.bottom).offset(10)
            make.height.equalTo(24)
        }

        progressBarFill.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
            // 68% progress
            make.width.equalToSuperview().multipliedBy(0.68)
        }

        progressDetailLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(14)
            make.top.equalTo(progressBarBg.snp.bottom).offset(10)
            make.bottom.equalToSuperview().inset(12)
        }

        // FAB (52×52, trailing 24, bottom safeArea 16)
        fabButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(24)
            make.bottom.equalTo(view.safeAreaLayoutGuide).inset(16)
            make.size.equalTo(52)
        }
    }

    private func setupProgressGradient() {
        let gradLayer = CAGradientLayer()
        gradLayer.colors = [
            UIColor.primary.cgColor,
            UIColor(hex: "#8D6E63").cgColor,
        ]
        gradLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradLayer.endPoint   = CGPoint(x: 1, y: 0.5)
        gradLayer.cornerRadius = 4
        progressBarFill.layer.addSublayer(gradLayer)
        highlightLayers.append((progressBarFill, gradLayer))
    }

    // MARK: - FAB Glass Style (BookshelfViewController와 동일한 스펙)

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

    // MARK: - Bindings

    private func bindActions() {
        backButton.rx.tap
            .subscribe(onNext: { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            })
            .disposed(by: disposeBag)

        fabButton.rx.tap
            .subscribe(onNext: { [weak self] in
                guard let self else { return }
                let cameraVC = CameraCollectionViewController()
                cameraVC.modalPresentationStyle = .fullScreen
                cameraVC.onDirectCollect = { [weak self] in
                    let directVC = DirectCollectViewController()
                    directVC.modalPresentationStyle = .pageSheet
                    self?.present(directVC, animated: true)
                }
                self.present(cameraVC, animated: true)
            })
            .disposed(by: disposeBag)

        timerButton.rx.tap
            .subscribe(onNext: { [weak self] in
                let vc = ReadingRecordViewController()
                self?.navigationController?.pushViewController(vc, animated: true)
            })
            .disposed(by: disposeBag)

        editButton.rx.tap
            .subscribe(onNext: {
                // TODO: 독서 진행률 편집
                print("편집 탭")
            })
            .disposed(by: disposeBag)
    }

    // MARK: - Helpers

    private func makeDot(alpha: CGFloat) -> UIView {
        let v = UIView()
        v.backgroundColor = UIColor.primary
        v.layer.cornerRadius = 3.5
        v.alpha = alpha
        return v
    }
}
