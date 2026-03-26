//
//  DirectRegisterViewController.swift
//  Under_line
//
//  FAB → 도서 등록(검색) → 직접 등록 버튼 탭 시 present되는 시트 (Node BXIp3)
//

import UIKit
import SnapKit
import RxSwift
import RxCocoa
import Toast

final class DirectRegisterViewController: UIViewController {

    private let disposeBag = DisposeBag()

    // MARK: - UI Components

    private let handleBar: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.walnut.withAlphaComponent(0.25)
        v.layer.cornerRadius = 2.5
        return v
    }()

    private let sheetTitleLabel: UILabel = {
        let l = UILabel()
        l.text = "도서 등록"
        l.font = UIFont(name: "GowunBatang-Bold", size: 22)
            ?? .systemFont(ofSize: 22, weight: .semibold)
        l.textColor = .accent
        return l
    }()

    private let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.showsVerticalScrollIndicator = false
        sv.alwaysBounceVertical = true
        sv.keyboardDismissMode = .onDrag
        return sv
    }()

    private let formStackView: UIStackView = {
        let sv = UIStackView()
        sv.axis    = .vertical
        sv.spacing = 20
        return sv
    }()

    // Section Top
    private let bookTitleField   = FormFieldView(label: "책 제목 *")
    private let authorField      = FormFieldView(label: "지은이 *")
    private let publisherField   = FormFieldView(label: "출판사 *")
    private let publishDateField = FormFieldView(label: "출판일", keyboardType: .numberPad, placeholder: "예 : 20260101")
    private let isbnField        = FormFieldView(label: "ISBN 번호 *", keyboardType: .numberPad)

    // Section Bottom
    private let coverURLField    = FormFieldView(label: "책 표지 이미지 URL", keyboardType: .URL, placeholder: "https://")
    private let categoryField    = FormFieldView(label: "도서 카테고리", placeholder: "예 : 소설, 에세이, 자기계발")
    private let descriptionField = FormDescriptionFieldView(label: "책 소개")

    private let registerButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("등록하기", for: .normal)
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
        setupUI()
        setupConstraints()
        bindActions()
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = UIColor.background

        view.addSubview(handleBar)
        view.addSubview(sheetTitleLabel)

        // Section Top (gap: 16)
        let sectionTop = UIStackView(arrangedSubviews: [
            bookTitleField,
            authorField,
            publisherField,
            publishDateField,
            isbnField,
        ])
        sectionTop.axis    = .vertical
        sectionTop.spacing = 16

        // Section Bottom (gap: 16)
        let sectionBottom = UIStackView(arrangedSubviews: [
            coverURLField,
            categoryField,
            descriptionField,
            registerButton,
        ])
        sectionBottom.axis    = .vertical
        sectionBottom.spacing = 16

        formStackView.addArrangedSubview(sectionTop)
        formStackView.addArrangedSubview(sectionBottom)

        scrollView.addSubview(formStackView)
        view.addSubview(scrollView)
    }

    private func setupConstraints() {
        // Drag handle
        handleBar.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(12)
            make.centerX.equalToSuperview()
            make.width.equalTo(36)
            make.height.equalTo(5)
        }

        // Sheet header (height=52, padding=[0,24])
        sheetTitleLabel.snp.makeConstraints { make in
            make.top.equalTo(handleBar.snp.bottom).offset(11)
            make.leading.trailing.equalToSuperview().inset(24)
            make.height.equalTo(52)
        }

        // Form scroll (top offset=5, padding=[5,24,24,24])
        scrollView.snp.makeConstraints { make in
            make.top.equalTo(sheetTitleLabel.snp.bottom).offset(5)
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide)
        }

        formStackView.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.bottom.equalToSuperview().inset(24)
            make.leading.trailing.equalToSuperview().inset(24)
            make.width.equalTo(scrollView).offset(-48)
        }

        registerButton.snp.makeConstraints { make in
            make.height.equalTo(52)
        }
    }

    // MARK: - Bindings

    private func bindActions() {
        bindValidation()

        registerButton.rx.tap
            .subscribe(onNext: { [weak self] in
                self?.handleRegister()
            })
            .disposed(by: disposeBag)
    }

    private func bindValidation() {
        Observable.combineLatest(
            bookTitleField.textField.rx.text.orEmpty,
            authorField.textField.rx.text.orEmpty,
            publisherField.textField.rx.text.orEmpty,
            isbnField.textField.rx.text.orEmpty
        ) { title, author, publisher, isbn in
            !title.trimmingCharacters(in: .whitespaces).isEmpty &&
            !author.trimmingCharacters(in: .whitespaces).isEmpty &&
            !publisher.trimmingCharacters(in: .whitespaces).isEmpty &&
            !isbn.trimmingCharacters(in: .whitespaces).isEmpty
        }
        .observe(on: MainScheduler.instance)
        .subscribe(onNext: { [weak self] isValid in
            self?.registerButton.isEnabled = isValid
            self?.registerButton.alpha = isValid ? 1.0 : 0.4
        })
        .disposed(by: disposeBag)
    }

    private func handleRegister() {
        let title       = bookTitleField.textField.text?.trimmingCharacters(in: .whitespaces) ?? ""
        let author      = authorField.textField.text?.trimmingCharacters(in: .whitespaces) ?? ""
        let publisher   = publisherField.textField.text?.trimmingCharacters(in: .whitespaces) ?? ""
        let isbn        = isbnField.textField.text?.trimmingCharacters(in: .whitespaces) ?? ""
        let publishDate = publishDateField.textField.text?.trimmingCharacters(in: .whitespaces)
        let coverURLStr = coverURLField.textField.text?.trimmingCharacters(in: .whitespaces)
        let categoryRaw = categoryField.textField.text?.trimmingCharacters(in: .whitespaces)
        let desc        = descriptionField.textView.text.trimmingCharacters(in: .whitespaces)

        let category = (categoryRaw?.isEmpty ?? true) ? "미정" : categoryRaw
        let coverURL  = coverURLStr.flatMap { $0.isEmpty ? nil : URL(string: $0) }

        let formattedDate: String? = {
            guard let raw = publishDate, raw.count == 8,
                  raw.allSatisfy(\.isNumber) else { return publishDate?.isEmpty == true ? nil : publishDate }
            return "\(raw.prefix(4))-\(raw.dropFirst(4).prefix(2))-\(raw.suffix(2))"
        }()

        let book = Book(
            title:       title,
            author:      author,
            isbn13:      isbn,
            coverURL:    coverURL,
            publisher:   publisher,
            publishDate: formattedDate,
            category:    category,
            bestRank:    nil,
            description: desc
        )

        AppContainer.shared.bookRepository.saveBook(book)
            .observe(on: MainScheduler.instance)
            .subscribe(
                onCompleted: { [weak self] in
                    // BookSearchVC를 띄운 상위 VC에서 dismiss → 체인 전체 동시 해제
                    self?.presentingViewController?.presentingViewController?.dismiss(animated: true)
                },
                onError: { [weak self] error in
                    var style = ToastStyle()
                    style.backgroundColor = UIColor.primary.withAlphaComponent(0.9)
                    style.messageFont = UIFont(name: "GowunBatang-Regular", size: 14) ?? .systemFont(ofSize: 14)
                    self?.view.makeToast(error.localizedDescription, duration: 1.5, position: .center, style: style)
                }
            )
            .disposed(by: disposeBag)
    }
}

// MARK: - FormFieldView

private final class FormFieldView: UIView {

    private let labelView: UILabel = {
        let l = UILabel()
        l.font = UIFont(name: "GoyangIlsan R", size: 14)
            ?? .systemFont(ofSize: 14, weight: .semibold)
        l.textColor = .accent
        return l
    }()

    private let inputContainer: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 10
        v.layer.borderWidth  = 1
        v.layer.borderColor  = UIColor.walnut.cgColor
        return v
    }()

    let textField: UITextField = {
        let tf = UITextField()
        tf.font = UIFont(name: "GoyangIlsan R", size: 14)
            ?? .systemFont(ofSize: 14)
        tf.textColor = .accent
        tf.backgroundColor = .clear
        return tf
    }()

    // 날짜 필드용
    private var datePicker: UIDatePicker?

    init(label: String, keyboardType: UIKeyboardType = .default, placeholder: String = "") {
        super.init(frame: .zero)
        labelView.text = label
        textField.keyboardType = keyboardType
        textField.attributedPlaceholder = NSAttributedString(string: placeholder, attributes: [NSAttributedString.Key.foregroundColor : UIColor.primary.withAlphaComponent(0.4)])
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        inputContainer.addSubview(textField)
        [labelView, inputContainer].forEach { addSubview($0) }

        labelView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
        }

        inputContainer.snp.makeConstraints { make in
            make.top.equalTo(labelView.snp.bottom).offset(8)
            make.leading.trailing.bottom.equalToSuperview()
            make.height.equalTo(48)
        }

        textField.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(16)
            make.centerY.equalToSuperview()
        }
    }
}

// MARK: - FormDescriptionFieldView

private final class FormDescriptionFieldView: UIView {

    private let labelView: UILabel = {
        let l = UILabel()
        l.font = UIFont(name: "GoyangIlsan R", size: 14)
            ?? .systemFont(ofSize: 14, weight: .semibold)
        l.textColor = .accent
        return l
    }()

    private let inputContainer: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 10
        v.layer.borderWidth  = 1
        v.layer.borderColor  = UIColor.walnut.cgColor
        return v
    }()

    let textView: UITextView = {
        let tv = UITextView()
        tv.font = UIFont(name: "GoyangIlsan R", size: 14)
            ?? .systemFont(ofSize: 14)
        tv.textColor = .accent
        tv.backgroundColor = .clear
        tv.isScrollEnabled = false
        return tv
    }()

    init(label: String) {
        super.init(frame: .zero)
        labelView.text = label
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        inputContainer.addSubview(textView)
        [labelView, inputContainer].forEach { addSubview($0) }

        labelView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
        }

        inputContainer.snp.makeConstraints { make in
            make.top.equalTo(labelView.snp.bottom).offset(8)
            make.leading.trailing.bottom.equalToSuperview()
            make.height.equalTo(120)
        }

        textView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(12)
        }
    }
}
