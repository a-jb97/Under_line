//
//  PageRecordViewController.swift
//  Under_line
//
//  독서 진행률 편집 화면 — editButton 탭 시 pageSheet으로 present
//

import UIKit
import SnapKit
import RxSwift
import RxCocoa
import Toast

final class PageRecordViewController: UIViewController {

    var onPageRecorded: ((Int) -> Void)?

    private let itemPage: Int
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
        l.text = "독서 진행률"
        l.font = UIFont(name: "GowunBatang-Bold", size: 22)
            ?? .systemFont(ofSize: 22, weight: .semibold)
        l.textColor = .accent
        return l
    }()

    private let fieldLabel: UILabel = {
        let l = UILabel()
        l.text = "읽은 페이지"
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

    private let pageTextField: UITextField = {
        let tf = UITextField()
        tf.keyboardType = .numberPad
        tf.font = UIFont(name: "GoyangIlsan R", size: 14)
            ?? .systemFont(ofSize: 14)
        tf.textColor = .accent
        tf.backgroundColor = .clear
        return tf
    }()

    private let recordButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("페이지 기록", for: .normal)
        btn.titleLabel?.font = UIFont(name: "GowunBatang-Bold", size: 18)
            ?? .boldSystemFont(ofSize: 18)
        btn.setTitleColor(UIColor.background, for: .normal)
        btn.backgroundColor = UIColor.walnut
        btn.layer.cornerRadius = 12
        return btn
    }()

    // MARK: - Init

    init(itemPage: Int) {
        self.itemPage = itemPage
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupConstraints()
        bindActions()
        configureSheet()
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = UIColor.background
        view.addSubview(handleBar)
        view.addSubview(sheetTitleLabel)
        view.addSubview(fieldLabel)
        inputContainer.addSubview(pageTextField)
        view.addSubview(inputContainer)
        view.addSubview(recordButton)
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

        fieldLabel.snp.makeConstraints { make in
            make.top.equalTo(sheetTitleLabel.snp.bottom).offset(5)
            make.leading.trailing.equalToSuperview().inset(24)
        }

        inputContainer.snp.makeConstraints { make in
            make.top.equalTo(fieldLabel.snp.bottom).offset(8)
            make.leading.trailing.equalToSuperview().inset(24)
            make.height.equalTo(48)
        }

        pageTextField.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(16)
            make.centerY.equalToSuperview()
        }

        recordButton.snp.makeConstraints { make in
            make.top.equalTo(inputContainer.snp.bottom).offset(20)
            make.leading.trailing.equalToSuperview().inset(24)
            make.height.equalTo(52)
        }
    }

    private func configureSheet() {
        guard let sheet = sheetPresentationController else { return }
        // handleBar(17) + sheetTitleLabel(63) + fieldLabel(22) + inputContainer(56) + recordButton(72) + bottom(16) = 246
        let detent = UISheetPresentationController.Detent.custom { _ in 246 }
        sheet.detents = [detent]
        sheet.prefersGrabberVisible = false
    }

    // MARK: - Bindings

    private func bindActions() {
        let isNonEmpty = pageTextField.rx.text.orEmpty
            .asDriver()
            .map { !$0.isEmpty }

        isNonEmpty
            .drive(recordButton.rx.isEnabled)
            .disposed(by: disposeBag)

        isNonEmpty
            .map { $0 ? CGFloat(1.0) : CGFloat(0.4) }
            .drive(recordButton.rx.alpha)
            .disposed(by: disposeBag)

        recordButton.rx.tap
            .withLatestFrom(pageTextField.rx.text.orEmpty)
            .subscribe(onNext: { [weak self] text in
                guard let self, let page = Int(text) else { return }
                if page > self.itemPage {
                    var style = ToastStyle()
                    style.backgroundColor = UIColor.appPrimary.withAlphaComponent(0.9)
                    style.messageFont = UIFont(name: "GowunBatang-Regular", size: 14) ?? .systemFont(ofSize: 14)
                    self.view.window?.makeToast(
                        "전체 페이지보다 많은 페이지는 기록할 수 없습니다.",
                        duration: 1.5,
                        position: .center,
                        style: style
                    )
                    return
                }
                self.onPageRecorded?(page)
                self.dismiss(animated: true)
            })
            .disposed(by: disposeBag)
    }
}
