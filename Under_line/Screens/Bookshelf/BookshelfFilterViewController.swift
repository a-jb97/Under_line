//
//  BookshelfFilterViewController.swift
//  Under_line
//
//  책장 필터 시트 — 책 제목/저자로 검색 후 선반 필터링
//

import UIKit
import SnapKit
import RxSwift
import RxCocoa

protocol BookshelfFilterDelegate: AnyObject {
    func bookshelfFilter(didSearch query: String)
    func bookshelfFilterDidRequestShowAll()
}

final class BookshelfFilterViewController: UIViewController {

    weak var delegate: BookshelfFilterDelegate?

    private let disposeBag = DisposeBag()

    /// 시트 최적 높이: 전부표시 버튼 하단 + 16pt
    static var preferredSheetHeight: CGFloat {
        let font = UIFont(name: "GowunBatang-Bold", size: 20) ?? .systemFont(ofSize: 20, weight: .bold)
        let titleH = ceil(font.lineHeight)
        // top(20) + title + gap(12) + searchBar(48) + gap(16) + divider(1) + gap(16) + button(48) + bottom(16)
        return 20 + titleH + 12 + 48 + 16 + 1 + 16 + 48 + 16
    }

    // MARK: - UI

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.text = "책 검색"
        l.font = UIFont(name: "GowunBatang-Bold", size: 20)
            ?? .systemFont(ofSize: 20, weight: .bold)
        l.textColor = UIColor.accent
        return l
    }()

    private let searchBarView: UIView = {
        let v = UIView()
        v.backgroundColor    = UIColor.background
        v.layer.cornerRadius = 10
        v.layer.borderWidth  = 1
        v.layer.borderColor  = UIColor.walnut.cgColor
        return v
    }()

    private let searchIconView: UIImageView = {
        let iv = UIImageView()
        let cfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        iv.image       = UIImage(systemName: "magnifyingglass", withConfiguration: cfg)
        iv.tintColor   = UIColor.walnut
        iv.contentMode = .scaleAspectFit
        return iv
    }()

    private let searchTextField: UITextField = {
        let tf = UITextField()
        let placeholderFont = UIFont(name: "GoyangIlsan R", size: 14)
            ?? .systemFont(ofSize: 14)
        tf.attributedPlaceholder = NSAttributedString(
            string: "제목 또는 저자",
            attributes: [
                .font:            placeholderFont,
                .foregroundColor: UIColor(hex: "#190e0b").withAlphaComponent(0.5),
            ]
        )
        tf.font            = placeholderFont
        tf.textColor       = UIColor(hex: "#190e0b")
        tf.backgroundColor = .clear
        tf.returnKeyType   = .search
        return tf
    }()

    private let divider: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.appPrimary.withAlphaComponent(0.2)
        return v
    }()

    private lazy var showAllButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("전부 표시", for: .normal)
        btn.setTitleColor(UIColor.appPrimary, for: .normal)
        btn.titleLabel?.font = UIFont(name: "GowunBatang-Regular", size: 16)
            ?? .systemFont(ofSize: 16)
        btn.backgroundColor    = UIColor.appPrimary.withAlphaComponent(0.1)
        btn.layer.cornerRadius = 12
        btn.clipsToBounds      = true
        return btn
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupConstraints()
        bindActions()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        searchTextField.becomeFirstResponder()
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = UIColor.background

        searchBarView.addSubview(searchIconView)
        searchBarView.addSubview(searchTextField)

        view.addSubview(titleLabel)
        view.addSubview(searchBarView)
        view.addSubview(divider)
        view.addSubview(showAllButton)
    }

    private func bindActions() {
        searchTextField.rx.controlEvent(.editingDidEndOnExit)
            .withLatestFrom(searchTextField.rx.text.orEmpty)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .subscribe(onNext: { [weak self] query in
                self?.delegate?.bookshelfFilter(didSearch: query)
            })
            .disposed(by: disposeBag)

        showAllButton.rx.tap
            .subscribe(onNext: { [weak self] in
                self?.delegate?.bookshelfFilterDidRequestShowAll()
            })
            .disposed(by: disposeBag)
    }

    private func setupConstraints() {
        titleLabel.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(20)
            make.leading.trailing.equalToSuperview().inset(24)
        }

        searchBarView.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(12)
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

        divider.snp.makeConstraints { make in
            make.top.equalTo(searchBarView.snp.bottom).offset(16)
            make.leading.trailing.equalToSuperview().inset(24)
            make.height.equalTo(1)
        }

        showAllButton.snp.makeConstraints { make in
            make.top.equalTo(divider.snp.bottom).offset(16)
            make.leading.trailing.equalToSuperview().inset(24)
            make.height.equalTo(48)
        }
    }

}
