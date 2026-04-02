//
//  RandomUnderLineViewController.swift
//  Under_line
//
//  앱 실행 시 랜덤 문장을 표시하는 모달 (overFullScreen)
//  BookDetailViewController의 quoteCard와 동일한 디자인
//  모달 바깥을 탭하면 dismiss
//

import UIKit
import SnapKit
import RxSwift
import RxCocoa

final class RandomUnderLineViewController: UIViewController {

    private let disposeBag = DisposeBag()
    private let sentence: Sentence

    init(sentence: Sentence) {
        self.sentence = sentence
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Views

    /// 탭으로 dismiss 처리 (Rule 3: UIButton, not UIView+gesture)
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

    private let cardView: UIView = {
        let v = UIView()
        v.backgroundColor = .white
        v.layer.cornerRadius  = 16
        v.layer.shadowColor   = UIColor.black.cgColor
        v.layer.shadowOpacity = Float(CGFloat(0x26) / 255)
        v.layer.shadowRadius  = 12
        v.layer.shadowOffset  = CGSize(width: 0, height: 8)
        return v
    }()

    private let textLabel: UILabel = {
        let l = UILabel()
        l.numberOfLines = 0
        l.textAlignment = .center
        l.isUserInteractionEnabled = false
        return l
    }()

    private let pageLabel: UILabel = {
        let l = UILabel()
        l.font = UIFont(name: "GoyangIlsan R", size: 13) ?? .systemFont(ofSize: 13)
        l.textColor = UIColor.appPrimary.withAlphaComponent(0.5)
        l.textAlignment = .right
        l.isUserInteractionEnabled = false
        return l
    }()

    private let emotionImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.isUserInteractionEnabled = false
        return iv
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        setupUI()
        setupConstraints()
        configure(with: sentence)
        bindActions()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    // MARK: - Setup

    private func setupUI() {
        // dismissButton은 가장 아래 (카드보다 뒤)
        view.addSubview(dismissButton)
        view.addSubview(dimView)
        view.addSubview(cardView)

        cardView.addSubview(textLabel)
        cardView.addSubview(pageLabel)
        cardView.addSubview(emotionImageView)
    }

    private func setupConstraints() {
        dismissButton.snp.makeConstraints { make in make.edges.equalToSuperview() }
        dimView.snp.makeConstraints { make in make.edges.equalToSuperview() }

        cardView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(32)
            make.height.equalTo(cardView.snp.width).multipliedBy(0.7)
            make.center.equalToSuperview()
        }

        textLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(24)
            make.center.equalToSuperview()
        }

        pageLabel.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(24)
            make.bottom.equalToSuperview().inset(20)
        }

        emotionImageView.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(20)
            make.bottom.equalToSuperview().inset(16)
            make.size.equalTo(18)
        }
    }

    // MARK: - Configure

    private func configure(with sentence: Sentence) {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.2
        style.alignment = .center

        textLabel.attributedText = NSAttributedString(
            string: sentence.sentence,
            attributes: [
                .font:            UIFont(name: "GowunBatang-Regular", size: 18) ?? .systemFont(ofSize: 18),
                .foregroundColor: UIColor.appPrimary,
                .paragraphStyle:  style,
            ]
        )
        pageLabel.text       = "p.\(sentence.page)"
        emotionImageView.image = sentence.emotion.emoji
    }

    // MARK: - Bindings

    private func bindActions() {
        dismissButton.rx.tap
            .subscribe(onNext: { [weak self] in
                self?.dismiss(animated: true)
            })
            .disposed(by: disposeBag)
    }
}
