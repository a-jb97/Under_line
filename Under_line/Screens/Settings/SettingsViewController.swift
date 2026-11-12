//
//  SettingsViewController.swift
//  Under_line
//
//  설정 탭 — 백업 / 불러오기 / 의견 보내기 / 앱 리뷰 / 이용약관 / 버전
//

import UIKit
import SnapKit
import RxSwift
import RxCocoa
import UniformTypeIdentifiers
import Toast

final class SettingsViewController: UIViewController {

    private let viewModel = SettingsViewModel()
    private let restoreFilePickedRelay = PublishRelay<URL>()
    private let disposeBag = DisposeBag()

    private let preferenceSelected = PublishRelay<BookPurchasePreference>()
    private var currentPreference = BookPurchasePreference.askEveryTime
    private let scrollView = UIScrollView()
    private let purchaseValueLabel = UILabel()
    private lazy var purchaseRow: UIButton = {
        let row = makeChevronRow(title: "도서 구매 서점")
        let title = row.subviews.compactMap { $0 as? UILabel }.first!
        title.snp.remakeConstraints { make in
            make.leading.equalToSuperview().inset(24)
            make.top.equalToSuperview().offset(6)
        }
        purchaseValueLabel.font = UIFont(name: "GowunBatang-Regular", size: 12) ?? .systemFont(ofSize: 12)
        purchaseValueLabel.textColor = .appPrimary
        purchaseValueLabel.isUserInteractionEnabled = false
        row.addSubview(purchaseValueLabel)
        purchaseValueLabel.snp.makeConstraints { make in
            make.leading.equalTo(title)
            make.top.equalTo(title.snp.bottom).offset(2)
        }
        return row
    }()

    private var isImportMode = false

    // MARK: - UI

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.text = "설정"
        l.font = UIFont(name: "GowunBatang-Bold", size: 34)
            ?? .systemFont(ofSize: 34, weight: .bold)
        l.textColor = .accent
        return l
    }()

    private let tableSection: UIView = {
        let v = UIView()
        v.backgroundColor = .clear
        return v
    }()

    private lazy var backupRow:          UIButton = makeChevronRow(title: "내 밑줄 기록 백업하기")
    private lazy var restoreRow:         UIButton = makeChevronRow(title: "내 밑줄 기록 불러오기")
    private lazy var randomUnderLineRow: UIButton = makeChevronRow(title: "랜덤 밑줄 기능 켜기/끄기")
    private lazy var tutorialRow:        UIButton = makeChevronRow(title: "튜토리얼 다시 보기")
    private lazy var feedbackRow: UIButton = makeChevronRow(title: "의견 보내기")
    private lazy var reviewRow:   UIButton = makeChevronRow(title: "앱 리뷰 작성하기")
    private lazy var termsRow:    UIButton = makeChevronRow(title: "개인정보 처리방침")
    private lazy var versionRow:  UIView   = makeVersionRow(
        title: "앱 버전",
        version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
    )

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .background
        setupUI()
        setupConstraints()
        bindActions()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scrollView.scrollRectToVisible(purchaseRow.convert(purchaseRow.bounds, to: scrollView), animated: false)
        view.layoutIfNeeded()
        TutorialSupport.show(on: self, key: "tutorial.purchaseSettings", steps: [
            TutorialStep(targetFrame: .zero, message: "기본 구매 서점을 지정하면 바로 연결돼요\n‘구매할 때마다 선택’으로 바꿀 수도 있어요", targetFrameProvider: { [weak self] in
                guard let row = self?.purchaseRow else { return .zero }
                return row.convert(row.bounds, to: nil)
            })
        ])
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }

    // MARK: - Setup

    private func setupUI() {
        view.addSubview(titleLabel)
        view.addSubview(scrollView)
        scrollView.addSubview(tableSection)

        let rows: [(UIView, Bool)] = [
            (backupRow,          true),
            (restoreRow,         true),
            (randomUnderLineRow, true),
            (purchaseRow, true),
            (tutorialRow,        true),
            (feedbackRow, true),
            (reviewRow,   true),
            (termsRow,    true),
            (versionRow,  false),
        ]

        var previous: UIView? = nil
        for (row, hasSeparator) in rows {
            tableSection.addSubview(row)
            row.snp.makeConstraints { make in
                make.leading.trailing.equalToSuperview()
                make.height.equalTo(52)
                if let prev = previous {
                    make.top.equalTo(prev.snp.bottom)
                } else {
                    make.top.equalToSuperview()
                }
            }

            if hasSeparator {
                let sep = UIView()
                sep.backgroundColor = UIColor.appPrimary.withAlphaComponent(0.12)
                row.addSubview(sep)
                sep.snp.makeConstraints { make in
                    make.leading.equalToSuperview().inset(24)
                    make.trailing.bottom.equalToSuperview()
                    make.height.equalTo(1)
                }
            }

            previous = row
        }

        if let last = previous {
            tableSection.snp.makeConstraints { make in
                make.bottom.equalTo(last.snp.bottom)
            }
        }
    }

    private func setupConstraints() {
        titleLabel.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(8)
            make.leading.greaterThanOrEqualToSuperview().inset(24)
            make.width.lessThanOrEqualTo(600)
            make.width.equalToSuperview().priority(.high)
            make.centerX.equalToSuperview()
        }

        scrollView.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(28)
            make.leading.trailing.bottom.equalTo(view.safeAreaLayoutGuide)
        }
        scrollView.contentLayoutGuide.snp.makeConstraints { make in
            make.width.equalTo(scrollView.frameLayoutGuide)
        }
        tableSection.snp.makeConstraints { make in
            make.top.bottom.equalTo(scrollView.contentLayoutGuide)
            make.centerX.equalTo(scrollView.frameLayoutGuide)
            make.width.equalTo(scrollView.frameLayoutGuide).priority(.high)
            make.width.lessThanOrEqualTo(600)
        }
    }

    // MARK: - Row Factory

    private func makeChevronRow(title: String) -> UIButton {
        let container = UIButton(type: .custom)
        container.backgroundColor = .clear

        let label = UILabel()
        label.text = title
        label.font = UIFont(name: "GowunBatang-Regular", size: 16)
            ?? .systemFont(ofSize: 16)
        label.textColor = .accent
        label.isUserInteractionEnabled = false

        let icon = UIImageView()
        icon.image = UIImage(systemName: "chevron.right",
                             withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .regular))
        icon.tintColor = .appPrimary
        icon.contentMode = .scaleAspectFit
        icon.isUserInteractionEnabled = false

        container.addSubview(label)
        container.addSubview(icon)

        label.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(24)
            make.centerY.equalToSuperview()
        }
        icon.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(24)
            make.centerY.equalToSuperview()
            make.size.equalTo(18)
        }

        return container
    }

    private func makeVersionRow(title: String, version: String) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear

        let label = UILabel()
        label.text = title
        label.font = UIFont(name: "GowunBatang-Regular", size: 16)
            ?? .systemFont(ofSize: 16)
        label.textColor = .accent

        let versionLabel = UILabel()
        versionLabel.text = version
        versionLabel.font = UIFont(name: "GowunBatang-Regular", size: 16)
            ?? .systemFont(ofSize: 16)
        versionLabel.textColor = UIColor.appPrimary.withAlphaComponent(0.5)

        container.addSubview(label)
        container.addSubview(versionLabel)

        label.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(24)
            make.centerY.equalToSuperview()
        }
        versionLabel.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(24)
            make.centerY.equalToSuperview()
        }

        return container
    }

    // MARK: - Bindings

    private func bindActions() {
        let output = viewModel.transform(input: SettingsViewModel.Input(
            preferenceSelected: preferenceSelected.asObservable(),
            backupTap:         backupRow.rx.tap.asObservable(),
            restoreFilePicked: restoreFilePickedRelay.asObservable()
        ))

        output.purchasePreference.drive(onNext: { [weak self] value in
            self?.currentPreference = value
            self?.purchaseValueLabel.text = value.displayName
        }).disposed(by: disposeBag)
        purchaseRow.rx.tap.subscribe(onNext: { [weak self] in
            guard let self, self.presentedViewController == nil else { return }
            let menu = UIAlertController(title: "도서 구매 서점", message: "현재: \(self.currentPreference.displayName)", preferredStyle: .alert)
            let options = BookStore.allCases.map { BookPurchasePreference.store($0) } + [.askEveryTime]
            for option in options {
                menu.addAction(UIAlertAction(title: option.displayName, style: .default) { [weak self] _ in
                    self?.preferenceSelected.accept(option)
                })
            }
            menu.addAction(UIAlertAction(title: "취소", style: .cancel))
            self.present(menu, animated: true)
        }).disposed(by: disposeBag)

        output.exportFileURL
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] url in
                guard let self else { return }
                let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
                picker.delegate = self
                self.isImportMode = false
                self.present(picker, animated: true)
            })
            .disposed(by: disposeBag)

        output.toastMessage
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] message in
                var style = ToastStyle()
                style.backgroundColor = UIColor.appPrimary.withAlphaComponent(0.9)
                style.messageFont = UIFont(name: "GowunBatang-Regular", size: 14) ?? .systemFont(ofSize: 14)
                self?.view.makeToast(message, duration: 1.2, position: .center, style: style)
            })
            .disposed(by: disposeBag)

        output.restoreSucceeded
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] in
                guard let tabBar = self?.tabBarController else { return }
                tabBar.selectedIndex = 0
                if let nav = tabBar.viewControllers?.first as? UINavigationController {
                    nav.popToRootViewController(animated: false)
                    if let bookshelf = nav.viewControllers.first as? BookshelfViewController {
                        bookshelf.showRestoreCompleteAlert()
                    }
                }
            })
            .disposed(by: disposeBag)

        restoreRow.rx.tap
            .subscribe(onNext: { [weak self] in
                guard let self else { return }
                let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json])
                picker.delegate = self
                self.isImportMode = true
                self.present(picker, animated: true)
            })
            .disposed(by: disposeBag)

        randomUnderLineRow.rx.tap
            .subscribe(onNext: { [weak self] in
                guard let self else { return }
                let isEnabled = !UserDefaults.standard.bool(forKey: "randomUnderLine.isDisabled")
                let alert = UIAlertController(
                    title:   "랜덤 밑줄 기능",
                    message: isEnabled
                        ? "앱 실행 시 감정을 선택해 랜덤 문장을 표시하는 기능을 끄시겠습니까?"
                        : "앱 실행 시 감정을 선택해 랜덤 문장을 표시하는 기능을 켜시겠습니까?",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "취소", style: .cancel))
                alert.addAction(UIAlertAction(
                    title: isEnabled ? "끄기" : "켜기",
                    style: isEnabled ? .destructive : .default
                ) { _ in
                    UserDefaults.standard.set(isEnabled, forKey: "randomUnderLine.isDisabled")
                })
                self.present(alert, animated: true)
            })
            .disposed(by: disposeBag)

        tutorialRow.rx.tap
            .subscribe(onNext: { [weak self] in
                TutorialSupport.keys
                    .forEach { UserDefaults.standard.removeObject(forKey: $0) }
                guard let tabBar = self?.tabBarController else { return }
                tabBar.selectedIndex = 0
                if let nav = tabBar.viewControllers?.first as? UINavigationController {
                    nav.popToRootViewController(animated: false)
                }
            })
            .disposed(by: disposeBag)

        feedbackRow.rx.tap
            .subscribe(onNext: { _ in
                guard let url = URL(string: "mailto:a_jb97@naver.com") else { return }
                UIApplication.shared.open(url)
            })
            .disposed(by: disposeBag)

        reviewRow.rx.tap
            .subscribe(onNext: { _ in
                guard let url = URL(string: "https://apps.apple.com/app/id6761336410?action=write-review") else { return }
                UIApplication.shared.open(url)
            })
            .disposed(by: disposeBag)

        termsRow.rx.tap
            .subscribe(onNext: { _ in
                guard let url = URL(string: "https://tide-animal-6d1.notion.site/331dbf174e6680b6883fec57dc7d074f") else { return }
                UIApplication.shared.open(url)
            })
            .disposed(by: disposeBag)
    }
}

// MARK: - UIDocumentPickerDelegate

extension SettingsViewController: UIDocumentPickerDelegate {

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if isImportMode {
            guard let url = urls.first else { return }
            showRestoreConfirmAlert(url: url)
        } else {
            var style = ToastStyle()
            style.backgroundColor = UIColor.appPrimary.withAlphaComponent(0.9)
            style.messageFont = UIFont(name: "GowunBatang-Regular", size: 14) ?? .systemFont(ofSize: 14)
            view.makeToast("백업 파일이 저장되었습니다.", duration: 1.2, position: .center, style: style)
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        isImportMode = false
    }

    private func showRestoreConfirmAlert(url: URL) {
        let alert = UIAlertController(
            title:   "밑줄 기록 불러오기",
            message: "현재 저장된 모든 데이터가 백업 파일로 교체됩니다.\n계속하시겠습니까?",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "취소", style: .cancel))
        alert.addAction(UIAlertAction(title: "불러오기", style: .destructive) { [weak self] _ in
            self?.restoreFilePickedRelay.accept(url)
        })
        present(alert, animated: true)
    }
}
