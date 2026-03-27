//
//  SettingsViewController.swift
//  Under_line
//
//  설정 탭 — 백업 / 의견 보내기 / 앱 리뷰 / 이용약관 / 버전
//

import UIKit
import SnapKit
import RxSwift
import RxCocoa

final class SettingsViewController: UIViewController {

    private let disposeBag = DisposeBag()

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

    private lazy var backupRow:   UIButton = makeChevronRow(title: "내 밑줄 기록 백업하기")
    private lazy var feedbackRow: UIButton = makeChevronRow(title: "의견 보내기")
    private lazy var reviewRow:   UIButton = makeChevronRow(title: "앱 리뷰 작성하기")
    private lazy var termsRow:    UIButton = makeChevronRow(title: "서비스 이용약관")
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
        backupRow.rx.tap
            .subscribe(onNext: { [weak self] in
                // TODO: SwiftData 백업 기능 연결
                self?.showAlert(message: "백업 기능은 준비 중입니다.")
            })
            .disposed(by: disposeBag)

        feedbackRow.rx.tap
            .subscribe(onNext: { _ in
                guard let url = URL(string: "mailto:feedback@underline.app") else { return }
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
                // TODO: 실제 이용약관 URL로 교체
                guard let url = URL(string: "https://underline.app/terms") else { return }
                UIApplication.shared.open(url)
            })
            .disposed(by: disposeBag)
    }

    private func showAlert(message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "확인", style: .default))
        present(alert, animated: true)
    }
}
