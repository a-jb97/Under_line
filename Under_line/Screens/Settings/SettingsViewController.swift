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

    private lazy var backupRow:  UIButton = makeChevronRow(title: "내 밑줄 기록 백업하기")
    private lazy var restoreRow: UIButton = makeChevronRow(title: "내 밑줄 기록 불러오기")
    private lazy var feedbackRow: UIButton = makeChevronRow(title: "의견 보내기")
    private lazy var reviewRow:   UIButton = makeChevronRow(title: "앱 리뷰 작성하기")
    private lazy var termsRow:    UIButton = makeChevronRow(title: "개인정보 처리방침")
    private lazy var versionRow:  UIView   = makeVersionRow(title: "앱 버전", version: "1.0.0")

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .background
        setupUI()
        setupConstraints()
        bindActions()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }

    // MARK: - Setup

    private func setupUI() {
        view.addSubview(titleLabel)
        view.addSubview(tableSection)

        let rows: [(UIView, Bool)] = [
            (backupRow,   true),
            (restoreRow,  true),
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
                sep.backgroundColor = UIColor.primary.withAlphaComponent(0.12)
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
            make.leading.equalToSuperview().inset(24)
        }

        tableSection.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(28)
            make.leading.trailing.equalToSuperview()
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
        icon.tintColor = .primary
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
        versionLabel.textColor = UIColor.primary.withAlphaComponent(0.5)

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
            backupTap:         backupRow.rx.tap.asObservable(),
            restoreFilePicked: restoreFilePickedRelay.asObservable()
        ))

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
                self?.view.makeToast(message, duration: 2.5, position: .bottom)
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

        feedbackRow.rx.tap
            .subscribe(onNext: { _ in
                guard let url = URL(string: "a_jb97@naver.com") else { return }
                UIApplication.shared.open(url)
            })
            .disposed(by: disposeBag)

        reviewRow.rx.tap
            .subscribe(onNext: { _ in
                // TODO: 실제 App Store ID로 교체
                guard let url = URL(string: "https://apps.apple.com/app/id000000000") else { return }
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
            view.makeToast("백업 파일이 저장되었습니다.", duration: 2.5, position: .bottom)
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
