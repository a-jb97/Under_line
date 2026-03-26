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

    private lazy var backupRow    = makeRow(title: "내 밑줄 기록 백업하기", accessory: .chevron)
    private lazy var feedbackRow  = makeRow(title: "의견 보내기",           accessory: .chevron)
    private lazy var reviewRow    = makeRow(title: "앱 리뷰 작성하기",       accessory: .chevron)
    private lazy var termsRow     = makeRow(title: "서비스 이용약관",         accessory: .chevron)
    private lazy var versionRow   = makeRow(title: "앱 버전",               accessory: .version("1.0.0"))

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

    private enum AccessoryType {
        case chevron
        case version(String)
    }

    private func makeRow(title: String, accessory: AccessoryType) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear

        let label = UILabel()
        label.text = title
        label.font = UIFont(name: "GowunBatang-Regular", size: 16)
            ?? .systemFont(ofSize: 16)
        label.textColor = .accent

        container.addSubview(label)
        label.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(24)
            make.centerY.equalToSuperview()
        }

        switch accessory {
        case .chevron:
            let icon = UIImageView()
            icon.image = UIImage(systemName: "chevron.right",
                                 withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .regular))
            icon.tintColor = .primary
            icon.contentMode = .scaleAspectFit
            container.addSubview(icon)
            icon.snp.makeConstraints { make in
                make.trailing.equalToSuperview().inset(24)
                make.centerY.equalToSuperview()
                make.size.equalTo(18)
            }

        case .version(let ver):
            let versionLabel = UILabel()
            versionLabel.text = ver
            versionLabel.font = UIFont(name: "GowunBatang-Regular", size: 16)
                ?? .systemFont(ofSize: 16)
            versionLabel.textColor = UIColor.primary.withAlphaComponent(0.5)
            container.addSubview(versionLabel)
            versionLabel.snp.makeConstraints { make in
                make.trailing.equalToSuperview().inset(24)
                make.centerY.equalToSuperview()
            }
        }

        return container
    }

    // MARK: - Bindings

    private func bindActions() {
        let backupTap = UITapGestureRecognizer()
        backupRow.addGestureRecognizer(backupTap)
        backupTap.rx.event
            .subscribe(onNext: { [weak self] _ in
                // TODO: SwiftData 백업 기능 연결
                self?.showAlert(message: "백업 기능은 준비 중입니다.")
            })
            .disposed(by: disposeBag)

        let feedbackTap = UITapGestureRecognizer()
        feedbackRow.addGestureRecognizer(feedbackTap)
        feedbackTap.rx.event
            .subscribe(onNext: { _ in
                guard let url = URL(string: "mailto:feedback@underline.app") else { return }
                UIApplication.shared.open(url)
            })
            .disposed(by: disposeBag)

        let reviewTap = UITapGestureRecognizer()
        reviewRow.addGestureRecognizer(reviewTap)
        reviewTap.rx.event
            .subscribe(onNext: { _ in
                // TODO: 실제 App Store ID로 교체
                guard let url = URL(string: "https://apps.apple.com/app/id000000000") else { return }
                UIApplication.shared.open(url)
            })
            .disposed(by: disposeBag)

        let termsTap = UITapGestureRecognizer()
        termsRow.addGestureRecognizer(termsTap)
        termsTap.rx.event
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
