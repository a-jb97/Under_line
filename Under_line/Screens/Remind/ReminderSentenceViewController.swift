//
//  ReminderSentenceViewController.swift
//  Under_line
//
//  리마인드 알림 탭 후 표시되는 밑줄 카드 뷰
//  UIScrollView 수평 페이징 + 앞(문장)/뒤(메모) 카드 플립
//

import UIKit
import SnapKit
import RxSwift
import RxCocoa

final class ReminderSentenceViewController: UIViewController {

    private let sentences: [Sentence]
    private let dateLabelText: String
    private var flippedIDs: Set<UUID> = []
    private let disposeBag = DisposeBag()

    // MARK: - UI

    private let headerDateLabel: UILabel = {
        let l = UILabel()
        l.font = UIFont(name: "GowunBatang-Regular", size: 15)
            ?? .systemFont(ofSize: 15)
        l.textColor = UIColor.appPrimary.withAlphaComponent(0.7)
        return l
    }()

    private lazy var closeButton: UIButton = {
        let b = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        b.setImage(UIImage(systemName: "xmark", withConfiguration: cfg), for: .normal)
        b.tintColor = .appPrimary
        return b
    }()

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

    private let quoteScrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.isPagingEnabled = true
        sv.showsHorizontalScrollIndicator = false
        sv.clipsToBounds = true
        return sv
    }()

    private let pageControl: UIPageControl = {
        let pc = UIPageControl()
        pc.currentPageIndicatorTintColor = UIColor.appPrimary
        pc.pageIndicatorTintColor = UIColor.appPrimary.withAlphaComponent(0.3)
        pc.hidesForSinglePage = true
        return pc
    }()

    // MARK: - Init

    init(sentences: [Sentence], dateLabel: String) {
        self.sentences     = sentences
        self.dateLabelText = dateLabel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .background
        setupUI()
        setupConstraints()
        renderCards()
        bindActions()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }

    // MARK: - Setup

    private func setupUI() {
        view.addSubview(headerDateLabel)
        view.addSubview(closeButton)
        quoteScrollView.delegate = self
        quoteCard.addSubview(quoteScrollView)
        view.addSubview(quoteCard)
        view.addSubview(pageControl)

        headerDateLabel.text = dateLabelText
    }

    private func setupConstraints() {
        headerDateLabel.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(20)
            make.leading.equalToSuperview().inset(24)
            make.trailing.lessThanOrEqualTo(closeButton.snp.leading).offset(-8)
        }

        closeButton.snp.makeConstraints { make in
            make.centerY.equalTo(headerDateLabel)
            make.trailing.equalToSuperview().inset(24)
            make.size.equalTo(28)
        }

        let cardInset: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 100 : 24
        quoteCard.snp.makeConstraints { make in
            make.top.equalTo(headerDateLabel.snp.bottom).offset(24)
            make.leading.trailing.equalToSuperview().inset(cardInset)
            make.height.equalTo(quoteCard.snp.width).multipliedBy(0.7)
        }

        quoteScrollView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        pageControl.snp.makeConstraints { make in
            make.top.equalTo(quoteCard.snp.bottom).offset(16)
            make.centerX.equalToSuperview()
        }
    }

    // MARK: - Render

    private func renderCards() {
        quoteScrollView.subviews.forEach { $0.removeFromSuperview() }

        guard !sentences.isEmpty else {
            let placeholder = makePlaceholder()
            quoteScrollView.addSubview(placeholder)
            placeholder.snp.makeConstraints { make in
                make.edges.equalToSuperview()
                make.width.height.equalTo(quoteScrollView)
            }
            pageControl.numberOfPages = 0
            return
        }

        pageControl.numberOfPages = sentences.count
        pageControl.currentPage   = 0

        var prev: UIView? = nil
        for (i, sentence) in sentences.enumerated() {
            let page = makePageView(for: sentence)
            quoteScrollView.addSubview(page)
            page.snp.makeConstraints { make in
                make.top.bottom.equalToSuperview()
                make.width.height.equalTo(quoteScrollView)
                if let prev {
                    make.leading.equalTo(prev.snp.trailing)
                } else {
                    make.leading.equalToSuperview()
                }
                if i == sentences.count - 1 {
                    make.trailing.equalToSuperview()
                }
            }
            prev = page
        }
    }

    // MARK: - Bindings

    private func bindActions() {
        closeButton.rx.tap
            .subscribe(onNext: { [weak self] in
                self?.dismiss(animated: true)
            })
            .disposed(by: disposeBag)
    }

    // MARK: - Card Factory

    private func makePageView(for sentence: Sentence) -> UIView {
        let page = UIView()

        // ── Front (문장) ───────────────────────────────────────
        let frontView = UIView()
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.2
        style.alignment = .center

        let textLabel = UILabel()
        textLabel.numberOfLines = 0
        textLabel.textAlignment = .center
        textLabel.attributedText = NSAttributedString(
            string: sentence.sentence,
            attributes: [
                .font:            UIFont(name: "GowunBatang-Regular", size: 18) ?? .systemFont(ofSize: 18),
                .foregroundColor: UIColor.appPrimary,
                .paragraphStyle:  style,
            ]
        )

        let pageLabel = UILabel()
        pageLabel.text = "p.\(sentence.page)"
        pageLabel.font = UIFont(name: "GoyangIlsan R", size: 13) ?? .systemFont(ofSize: 13)
        pageLabel.textColor = UIColor.appPrimary.withAlphaComponent(0.5)
        pageLabel.textAlignment = .right

        let emotionImageView = UIImageView(image: sentence.emotion.emoji)
        emotionImageView.contentMode = .scaleAspectFit

        // 긴 문장 스크롤 지원 (BookDetailViewController와 동일 패턴)
        let textScrollView = UIScrollView()
        textScrollView.showsVerticalScrollIndicator = false
        textScrollView.showsHorizontalScrollIndicator = false
        textScrollView.alwaysBounceVertical = false

        let textContentView = UIView()
        textScrollView.addSubview(textContentView)
        textContentView.addSubview(textLabel)

        let textAreaView = UIView()
        textAreaView.clipsToBounds = true
        textAreaView.addSubview(textScrollView)

        frontView.addSubview(pageLabel)
        frontView.addSubview(emotionImageView)
        frontView.addSubview(textAreaView)

        pageLabel.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(24)
            make.bottom.equalToSuperview().inset(20)
        }
        emotionImageView.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(20)
            make.bottom.equalToSuperview().inset(16)
            make.size.equalTo(18)
        }
        textAreaView.snp.makeConstraints { make in
            make.top.equalToSuperview().inset(20)
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(pageLabel.snp.top).offset(-8)
        }
        textContentView.snp.makeConstraints { make in
            make.edges.equalTo(textScrollView.contentLayoutGuide)
            make.width.equalTo(textScrollView.frameLayoutGuide)
        }
        textLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(24)
            make.top.bottom.equalToSuperview()
        }
        textScrollView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.centerY.equalToSuperview()
            make.height.lessThanOrEqualToSuperview()
            make.height.equalTo(textContentView).priority(.medium)
        }

        page.addSubview(frontView)
        frontView.snp.makeConstraints { make in make.edges.equalToSuperview() }

        // ── Back (메모) ────────────────────────────────────────
        let backView = UIView()
        let memoStyle = NSMutableParagraphStyle()
        memoStyle.lineHeightMultiple = 1.5
        memoStyle.alignment = .center

        let memoLabel = UILabel()
        memoLabel.numberOfLines = 0
        memoLabel.textAlignment = .center
        if let memo = sentence.memo, !memo.isEmpty {
            memoLabel.attributedText = NSAttributedString(
                string: memo,
                attributes: [
                    .font:            UIFont(name: "GowunBatang-Regular", size: 16) ?? .systemFont(ofSize: 16),
                    .foregroundColor: UIColor.appPrimary,
                    .paragraphStyle:  memoStyle,
                ]
            )
        } else {
            memoLabel.attributedText = NSAttributedString(
                string: "등록된 메모 없음",
                attributes: [
                    .font:            UIFont(name: "GowunBatang-Regular", size: 16) ?? .systemFont(ofSize: 16),
                    .foregroundColor: UIColor.appPrimary.withAlphaComponent(0.35),
                    .paragraphStyle:  memoStyle,
                ]
            )
        }

        backView.addSubview(memoLabel)
        memoLabel.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(24)
            make.center.equalToSuperview()
        }

        page.addSubview(backView)
        backView.snp.makeConstraints { make in make.edges.equalToSuperview() }

        // 초기 flip 상태
        let isFlipped = flippedIDs.contains(sentence.id)
        frontView.isHidden = isFlipped
        backView.isHidden  = !isFlipped

        // 카드 플립 탭
        // UIButton 대신 UITapGestureRecognizer 사용: 내부 textScrollView pan 제스처와 충돌 방지
        let tapGesture = UITapGestureRecognizer()
        tapGesture.cancelsTouchesInView = false
        page.addGestureRecognizer(tapGesture)

        tapGesture.rx.event
            .subscribe(onNext: { [weak self, weak page, weak frontView, weak backView] _ in
                guard let self, let page, let frontView, let backView else { return }
                let nowFlipped = self.flippedIDs.contains(sentence.id)
                if nowFlipped {
                    self.flippedIDs.remove(sentence.id)
                } else {
                    self.flippedIDs.insert(sentence.id)
                }
                UIView.transition(with: page, duration: 0.45, options: .transitionFlipFromRight, animations: {
                    frontView.isHidden = !nowFlipped
                    backView.isHidden  =  nowFlipped
                })
            })
            .disposed(by: disposeBag)

        return page
    }

    private func makePlaceholder() -> UIView {
        let page = UIView()
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.2
        style.alignment = .center

        let label = UILabel()
        label.numberOfLines = 0
        label.textAlignment = .center
        label.attributedText = NSAttributedString(
            string: "해당 날짜의 밑줄이 없어요.",
            attributes: [
                .font:            UIFont(name: "GowunBatang-Regular", size: 18) ?? .systemFont(ofSize: 18),
                .foregroundColor: UIColor.appPrimary.withAlphaComponent(0.5),
                .paragraphStyle:  style,
            ]
        )
        page.addSubview(label)
        label.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(24)
            make.center.equalToSuperview()
        }
        return page
    }
}

// MARK: - UIScrollViewDelegate

extension ReminderSentenceViewController: UIScrollViewDelegate {

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        let page = Int(scrollView.contentOffset.x / scrollView.bounds.width)
        pageControl.currentPage = page
    }
}
