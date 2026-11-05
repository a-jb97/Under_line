//
//  PageRecordViewController.swift
//  Under_line
//
//  독서 진행률 편집 화면 — 전체/현재 페이지를 함께 입력
//

import UIKit
import SnapKit
import RxSwift
import RxCocoa
import Toast

final class PageRecordViewController: UIViewController {

    var onProgressRecorded: ((ReadingProgress) -> Void)?

    private let initialItemPage: Int?
    private let initialCurrentPage: Int?
    private let disposeBag = DisposeBag()
    private let viewModel: PageRecordViewModel

    private let handleBar: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.walnut.withAlphaComponent(0.25)
        view.layer.cornerRadius = 2.5
        return view
    }()

    private let sheetTitleLabel: UILabel = {
        let label = UILabel()
        label.text = "독서 진행률"
        label.font = UIFont(name: "GowunBatang-Bold", size: 22)
            ?? .systemFont(ofSize: 22, weight: .semibold)
        label.textColor = .accent
        return label
    }()

    private let itemPageLabel = PageRecordViewController.makeFieldLabel(title: "전체 페이지")
    private let currentPageLabel = PageRecordViewController.makeFieldLabel(title: "읽은 페이지")
    private let itemPageContainer = PageRecordViewController.makeInputContainer()
    private let currentPageContainer = PageRecordViewController.makeInputContainer()
    private let itemPageTextField = PageRecordViewController.makeTextField(placeholder: "예 : 320")
    private let currentPageTextField = PageRecordViewController.makeTextField(placeholder: "예 : 120")

    private let saveButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("저장하기", for: .normal)
        button.titleLabel?.font = UIFont(name: "GowunBatang-Bold", size: 18)
            ?? .boldSystemFont(ofSize: 18)
        button.setTitleColor(UIColor.background, for: .normal)
        button.backgroundColor = UIColor.walnut
        button.layer.cornerRadius = 12
        return button
    }()

    init(isbn13: String, itemPage: Int?, currentPage: Int?) {
        initialItemPage = itemPage
        initialCurrentPage = currentPage
        viewModel = PageRecordViewModel(
            isbn13: isbn13,
            repository: AppContainer.shared.bookRepository
        )
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupConstraints()
        configureInitialValues()
        bindViewModel()
        configureSheet()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        (initialItemPage == nil ? itemPageTextField : currentPageTextField).becomeFirstResponder()
    }

    private func setupUI() {
        view.backgroundColor = UIColor.background
        [handleBar, sheetTitleLabel, itemPageLabel, itemPageContainer,
         currentPageLabel, currentPageContainer, saveButton].forEach(view.addSubview)
        itemPageContainer.addSubview(itemPageTextField)
        currentPageContainer.addSubview(currentPageTextField)
    }

    private func setupConstraints() {
        handleBar.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(12)
            make.centerX.equalToSuperview()
            make.width.equalTo(36)
            make.height.equalTo(5)
        }
        sheetTitleLabel.snp.makeConstraints { make in
            make.top.equalTo(handleBar.snp.bottom).offset(11)
            make.leading.trailing.equalToSuperview().inset(24)
            make.height.equalTo(52)
        }
        itemPageLabel.snp.makeConstraints { make in
            make.top.equalTo(sheetTitleLabel.snp.bottom).offset(5)
            make.leading.trailing.equalToSuperview().inset(24)
        }
        itemPageContainer.snp.makeConstraints { make in
            make.top.equalTo(itemPageLabel.snp.bottom).offset(8)
            make.leading.trailing.equalToSuperview().inset(24)
            make.height.equalTo(48)
        }
        currentPageLabel.snp.makeConstraints { make in
            make.top.equalTo(itemPageContainer.snp.bottom).offset(16)
            make.leading.trailing.equalToSuperview().inset(24)
        }
        currentPageContainer.snp.makeConstraints { make in
            make.top.equalTo(currentPageLabel.snp.bottom).offset(8)
            make.leading.trailing.equalToSuperview().inset(24)
            make.height.equalTo(48)
        }
        [itemPageTextField, currentPageTextField].forEach { textField in
            textField.snp.makeConstraints { make in
                make.leading.trailing.equalToSuperview().inset(16)
                make.centerY.equalToSuperview()
            }
        }
        saveButton.snp.makeConstraints { make in
            make.top.equalTo(currentPageContainer.snp.bottom).offset(20)
            make.leading.trailing.equalToSuperview().inset(24)
            make.height.equalTo(52)
        }
    }

    private func configureInitialValues() {
        itemPageTextField.text = initialItemPage.map(String.init)
        currentPageTextField.text = initialCurrentPage.flatMap { $0 > 0 ? String($0) : nil }
    }

    private func bindViewModel() {
        let output = viewModel.transform(input: .init(
            itemPage: itemPageTextField.rx.text.orEmpty.asObservable(),
            currentPage: currentPageTextField.rx.text.orEmpty.asObservable(),
            saveTap: saveButton.rx.tap.asObservable()
        ))

        output.isSaveEnabled
            .drive(onNext: { [weak self] isEnabled in
                self?.saveButton.isEnabled = isEnabled
                self?.saveButton.alpha = isEnabled ? 1 : 0.4
            })
            .disposed(by: disposeBag)

        output.saveCompleted
            .emit(onNext: { [weak self] progress in
                self?.onProgressRecorded?(progress)
                self?.dismiss(animated: true)
            })
            .disposed(by: disposeBag)

        output.errorMessage
            .emit(onNext: { [weak self] message in
                var style = ToastStyle()
                style.backgroundColor = UIColor.appPrimary.withAlphaComponent(0.9)
                style.messageFont = UIFont(name: "GowunBatang-Regular", size: 14)
                    ?? .systemFont(ofSize: 14)
                self?.view.window?.makeToast(
                    message,
                    duration: 1.2,
                    position: .center,
                    style: style
                )
            })
            .disposed(by: disposeBag)
    }

    private func configureSheet() {
        guard let sheet = sheetPresentationController else { return }
        sheet.detents = [.custom { _ in 342 }]
        sheet.prefersGrabberVisible = false
    }

    private static func makeFieldLabel(title: String) -> UILabel {
        let label = UILabel()
        label.text = title
        label.font = UIFont(name: "GoyangIlsan R", size: 14)
            ?? .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .accent
        return label
    }

    private static func makeInputContainer() -> UIView {
        let view = UIView()
        view.layer.cornerRadius = 10
        view.layer.borderWidth = 1
        view.layer.borderColor = UIColor.walnut.cgColor
        return view
    }

    private static func makeTextField(placeholder: String) -> UITextField {
        let textField = UITextField()
        textField.keyboardType = .numberPad
        textField.font = UIFont(name: "GoyangIlsan R", size: 14) ?? .systemFont(ofSize: 14)
        textField.textColor = .accent
        textField.backgroundColor = .clear
        textField.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor.appPrimary.withAlphaComponent(0.4)]
        )
        return textField
    }
}
