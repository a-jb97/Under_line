//
//  BookSearchViewController.swift
//  Under_line
//
//  FAB 탭 시 present되는 도서 등록 검색 시트 (Node 588fl)
//

import UIKit
import SnapKit
import RxSwift
import RxCocoa

final class BookSearchViewController: UIViewController {

    private let disposeBag = DisposeBag()

    // MARK: - Placeholder Data (추후 ViewModel / BookRepository로 교체)

    private let placeholderBooks: [(rank: Int, title: String, author: String)] = [
        (1, "데미안",             "헤르만 헤세"),
        (2, "나미야 잡화점의 기적", "히가시노 게이고"),
        (3, "어린 왕자",           "생텍쥐페리"),
        (4, "1984",               "조지 오웰"),
        (5, "코스모스",            "칼 세이건"),
    ]

    // MARK: - UI Components

    private let handleBar: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.walnut.withAlphaComponent(0.25)
        v.layer.cornerRadius = 2.5
        return v
    }()

    private let sheetTitleLabel: UILabel = {
        let l = UILabel()
        l.text = "도서 검색"
        l.font = UIFont(name: "GowunBatang-Bold", size: 22)
            ?? .systemFont(ofSize: 22, weight: .semibold)
        l.textColor = UIColor(hex: "#190e0b")
        return l
    }()

    private let searchBarView: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.background
        v.layer.cornerRadius = 10
        v.layer.borderWidth = 1
        v.layer.borderColor = UIColor.walnut.cgColor
        return v
    }()

    private let searchIconView: UIImageView = {
        let iv = UIImageView()
        let cfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        iv.image = UIImage(systemName: "magnifyingglass", withConfiguration: cfg)
        iv.tintColor = UIColor.walnut
        iv.contentMode = .scaleAspectFit
        return iv
    }()

    private let searchTextField: UITextField = {
        let tf = UITextField()
        let placeholderFont = UIFont(name: "GoyangIlsan R", size: 14)
            ?? .systemFont(ofSize: 14)
        tf.attributedPlaceholder = NSAttributedString(
            string: "책 제목 또는 저자를 검색하세요",
            attributes: [
                .font:            placeholderFont,
                .foregroundColor: UIColor(hex: "#190e0b").withAlphaComponent(0.5),
            ]
        )
        tf.font      = placeholderFont
        tf.textColor = UIColor(hex: "#190e0b")
        tf.backgroundColor  = .clear
        tf.returnKeyType    = .search
        return tf
    }()

    private let directRegisterButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("직접 등록", for: .normal)
        btn.titleLabel?.font = UIFont(name: "GoyangIlsan R", size: 14)
            ?? .systemFont(ofSize: 14)
        btn.setTitleColor(UIColor.walnut, for: .normal)
        btn.contentEdgeInsets  = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        return btn
    }()

    private let resultsScrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.showsVerticalScrollIndicator = false
        sv.alwaysBounceVertical = true
        return sv
    }()

    private let resultsStackView: UIStackView = {
        let sv = UIStackView()
        sv.axis    = .vertical
        sv.spacing = 12
        return sv
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupConstraints()
        setupBookRows()
        bindActions()
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = UIColor.background

        view.addSubview(handleBar)
        view.addSubview(sheetTitleLabel)
        view.addSubview(directRegisterButton)

        searchBarView.addSubview(searchIconView)
        searchBarView.addSubview(searchTextField)
        view.addSubview(searchBarView)

        resultsScrollView.addSubview(resultsStackView)
        view.addSubview(resultsScrollView)
    }

    private func setupConstraints() {
        // Drag handle (Design: 36×5, top=12, centerX)
        handleBar.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(12)
            make.centerX.equalToSuperview()
            make.width.equalTo(36)
            make.height.equalTo(5)
        }

        // Sheet Header (Design: height=52, padding leading=24)
        sheetTitleLabel.snp.makeConstraints { make in
            make.top.equalTo(handleBar.snp.bottom).offset(11)
            make.leading.equalToSuperview().inset(24)
            make.trailing.lessThanOrEqualTo(directRegisterButton.snp.leading).offset(-12)
            make.height.equalTo(52)
        }

        directRegisterButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(24)
            make.centerY.equalTo(sheetTitleLabel)
        }

        // Search Area (Design: padding=[0,24,16,24])
        searchBarView.snp.makeConstraints { make in
            make.top.equalTo(sheetTitleLabel.snp.bottom)
            make.leading.trailing.equalToSuperview().inset(24)
            make.height.equalTo(48)
        }

        searchIconView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.centerY.equalToSuperview()
            make.size.equalTo(18)
        }

        searchTextField.snp.makeConstraints { make in
            make.leading.equalTo(searchIconView.snp.trailing).offset(10)
            make.trailing.equalToSuperview().inset(16)
            make.centerY.equalToSuperview()
        }

        // Results scroll (Design: padding=[0,24], gap=12)
        resultsScrollView.snp.makeConstraints { make in
            make.top.equalTo(searchBarView.snp.bottom).offset(16)
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide)
        }

        resultsStackView.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.bottom.equalToSuperview().inset(12)
            make.leading.trailing.equalToSuperview().inset(24)
            make.width.equalTo(resultsScrollView).offset(-48)
        }
    }

    private func setupBookRows() {
        for book in placeholderBooks {
            resultsStackView.addArrangedSubview(
                BookRowView(rank: book.rank, title: book.title, author: book.author)
            )
        }
    }

    // MARK: - Bindings

    private func bindActions() {
        // 키보드 return → 검색 실행 (TODO: ViewModel 연결)
        searchTextField.rx.controlEvent(.editingDidEndOnExit)
            .subscribe(onNext: { [weak self] in
                self?.searchTextField.resignFirstResponder()
            })
            .disposed(by: disposeBag)

        // 직접 등록 버튼 → DirectRegisterViewController 표시
        directRegisterButton.rx.tap
            .subscribe(onNext: { [weak self] in
                let vc = DirectRegisterViewController()
                if let sheet = vc.sheetPresentationController {
                    sheet.detents = [.large()]
                    sheet.prefersGrabberVisible = false
                    sheet.preferredCornerRadius = 24
                }
                self?.present(vc, animated: true)
            })
            .disposed(by: disposeBag)
    }
}

// MARK: - BookRowView

private final class BookRowView: UIView {

    private let rankLabel: UILabel = {
        let l = UILabel()
        l.font = UIFont(name: "GoyangIlsan L", size: 18) ?? .boldSystemFont(ofSize: 18)
        l.textColor = UIColor(hex: "#190e0b")
        l.textAlignment = .center
        l.setContentHuggingPriority(.required, for: .horizontal)
        return l
    }()

    private let thumbnailView: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.walnut
        v.layer.cornerRadius = 4
        return v
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = UIFont(name: "GowunBatang-Regular", size: 16)
            ?? .systemFont(ofSize: 16, weight: .medium)
        l.textColor = UIColor(hex: "#190e0b")
        l.numberOfLines = 2
        return l
    }()

    private let authorLabel: UILabel = {
        let l = UILabel()
        l.font = UIFont(name: "GowunBatang-Regular", size: 13)
            ?? .systemFont(ofSize: 13)
        l.textColor = UIColor.walnut
        return l
    }()

    private let registerButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("등록", for: .normal)
        btn.titleLabel?.font = UIFont(name: "GoyangIlsan R", size: 13)
            ?? .systemFont(ofSize: 13, weight: .medium)
        btn.setTitleColor(UIColor.walnut, for: .normal)
        btn.layer.cornerRadius = 7
        btn.layer.borderWidth  = 1
        btn.layer.borderColor  = UIColor.walnut.cgColor
        btn.contentEdgeInsets  = UIEdgeInsets(top: 7, left: 14, bottom: 7, right: 14)
        btn.setContentHuggingPriority(.required, for: .horizontal)
        return btn
    }()

    init(rank: Int, title: String, author: String) {
        super.init(frame: .zero)
        rankLabel.text  = "\(rank)"
        titleLabel.text = title
        authorLabel.text = author
        setupView()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupView() {
        backgroundColor = UIColor.background
        layer.cornerRadius  = 16
        layer.masksToBounds = false

        // Neumorphic — dark shadow (bottom-right): #5d4037 @0x30 ≈ 19%, blur=8, offset=(4,4)
        layer.shadowColor   = UIColor(hex: "#5d4037").cgColor
        layer.shadowOpacity = Float(CGFloat(0x30) / 255)
        layer.shadowRadius  = 4
        layer.shadowOffset  = CGSize(width: 4, height: 4)

        let textStack = UIStackView(arrangedSubviews: [titleLabel, authorLabel])
        textStack.axis    = .vertical
        textStack.spacing = 3

        [rankLabel, thumbnailView, textStack, registerButton].forEach { addSubview($0) }

        // Row minimum height: thumbnail(64) + top/bottom padding(14×2) = 92
        snp.makeConstraints { make in
            make.height.greaterThanOrEqualTo(92)
        }

        rankLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.centerY.equalToSuperview()
            make.width.equalTo(20)
        }

        thumbnailView.snp.makeConstraints { make in
            make.leading.equalTo(rankLabel.snp.trailing).offset(14)
            make.centerY.equalToSuperview()
            make.width.equalTo(48)
            make.height.equalTo(64)
        }

        textStack.snp.makeConstraints { make in
            make.leading.equalTo(thumbnailView.snp.trailing).offset(14)
            make.trailing.lessThanOrEqualTo(registerButton.snp.leading).offset(-14)
            make.centerY.equalToSuperview()
        }

        registerButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(16)
            make.centerY.equalToSuperview()
        }
    }
}
