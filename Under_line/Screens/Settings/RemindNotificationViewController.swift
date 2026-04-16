//
//  RemindNotificationViewController.swift
//  Under_line
//
//  리마인드 알림 설정 시트 — 주기(하루/일주일/한달/일년) + 시간 Picker + 완료 버튼
//

import UIKit
import SnapKit
import RxSwift
import RxCocoa
import Toast

final class RemindNotificationViewController: UIViewController {

    private let viewModel = RemindNotificationViewModel()
    private let selectedPeriodRelay: BehaviorRelay<Int?>
    private let disposeBag = DisposeBag()

    private let periodNames = ["하루", "일주일", "한 달", "일년"]

    // MARK: - UI

    private let grabberView: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.appPrimary.withAlphaComponent(0.3)
        v.layer.cornerRadius = 2.5
        return v
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.text = "리마인드 알림"
        l.font = UIFont(name: "GowunBatang-Bold", size: 22)
            ?? .systemFont(ofSize: 22, weight: .bold)
        l.textColor = .accent
        return l
    }()

    private let periodSectionLabel: UILabel = {
        let l = UILabel()
        l.text = "알림 주기"
        l.font = UIFont(name: "GowunBatang-Regular", size: 13)
            ?? .systemFont(ofSize: 13)
        l.textColor = UIColor.appPrimary.withAlphaComponent(0.6)
        return l
    }()

    private let tableView: UITableView = {
        let tv = UITableView()
        tv.backgroundColor = .clear
        tv.rowHeight = 52
        tv.isScrollEnabled = false
        tv.separatorColor = UIColor.appPrimary.withAlphaComponent(0.12)
        tv.separatorInset = UIEdgeInsets(top: 0, left: 24, bottom: 0, right: 0)
        tv.tableFooterView = UIView()
        tv.register(UITableViewCell.self, forCellReuseIdentifier: "PeriodCell")
        return tv
    }()

    private let timeSectionLabel: UILabel = {
        let l = UILabel()
        l.text = "알림 시간"
        l.font = UIFont(name: "GowunBatang-Regular", size: 13)
            ?? .systemFont(ofSize: 13)
        l.textColor = UIColor.appPrimary.withAlphaComponent(0.6)
        return l
    }()

    private let datePicker: UIDatePicker = {
        let dp = UIDatePicker()
        dp.datePickerMode = .time
        dp.preferredDatePickerStyle = .wheels
        dp.minuteInterval = 5
        dp.locale = Locale(identifier: "ko_KR")
        return dp
    }()

    private let confirmButton: UIButton = {
        let b = UIButton(type: .custom)
        b.setTitle("완료", for: .normal)
        b.setTitleColor(.background, for: .normal)
        b.titleLabel?.font = UIFont(name: "GowunBatang-Bold", size: 16)
            ?? .systemFont(ofSize: 16, weight: .bold)
        b.backgroundColor = .appPrimary
        b.layer.cornerRadius = 12
        b.alpha = 0.4
        b.isEnabled = false
        return b
    }()

    // MARK: - Init

    init() {
        let saved = UserDefaults.standard.object(forKey: "remind.period") as? Int
        selectedPeriodRelay = BehaviorRelay<Int?>(value: saved)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .background
        setupUI()
        setupConstraints()
        loadSavedTime()
        bindAll()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }

    // MARK: - Setup

    private func setupUI() {
        view.addSubview(grabberView)
        view.addSubview(titleLabel)
        view.addSubview(periodSectionLabel)
        view.addSubview(tableView)
        view.addSubview(timeSectionLabel)
        view.addSubview(datePicker)
        view.addSubview(confirmButton)

        tableView.dataSource = self
    }

    private func setupConstraints() {
        grabberView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(12)
            make.centerX.equalToSuperview()
            make.width.equalTo(36)
            make.height.equalTo(5)
        }

        titleLabel.snp.makeConstraints { make in
            make.top.equalTo(grabberView.snp.bottom).offset(20)
            make.leading.equalToSuperview().inset(24)
        }

        periodSectionLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(24)
            make.leading.equalToSuperview().inset(24)
        }

        tableView.snp.makeConstraints { make in
            make.top.equalTo(periodSectionLabel.snp.bottom).offset(6)
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(52 * 4)
        }

        timeSectionLabel.snp.makeConstraints { make in
            make.top.equalTo(tableView.snp.bottom).offset(24)
            make.leading.equalToSuperview().inset(24)
        }

        datePicker.snp.makeConstraints { make in
            make.top.equalTo(timeSectionLabel.snp.bottom).offset(8)
            make.leading.trailing.equalToSuperview()
        }

        confirmButton.snp.makeConstraints { make in
            make.top.equalTo(datePicker.snp.bottom).offset(16)
            make.leading.trailing.equalToSuperview().inset(24)
            make.height.equalTo(52)
            make.bottom.lessThanOrEqualTo(view.safeAreaLayoutGuide).inset(24)
        }
    }

    private func loadSavedTime() {
        let savedInterval = UserDefaults.standard.double(forKey: "remind.time")
        if savedInterval > 0 {
            datePicker.date = Date(timeIntervalSinceReferenceDate: savedInterval)
        } else {
            var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            comps.hour = 9
            comps.minute = 0
            if let defaultDate = Calendar.current.date(from: comps) {
                datePicker.date = defaultDate
            }
        }
    }

    // MARK: - Bindings

    private func bindAll() {
        let output = viewModel.transform(input: RemindNotificationViewModel.Input(
            periodSelected: selectedPeriodRelay.asObservable(),
            timePicked:     datePicker.rx.value.asObservable(),
            confirmTap:     confirmButton.rx.tap.asObservable()
        ))

        output.isConfirmEnabled
            .drive(onNext: { [weak self] enabled in
                self?.confirmButton.isEnabled = enabled
                self?.confirmButton.alpha = enabled ? 1.0 : 0.4
            })
            .disposed(by: disposeBag)

        output.toastMessage
            .emit(onNext: { [weak self] message in
                guard let self else { return }
                var style = ToastStyle()
                style.backgroundColor = UIColor.appPrimary.withAlphaComponent(0.9)
                style.messageFont = UIFont(name: "GowunBatang-Regular", size: 14)
                    ?? .systemFont(ofSize: 14)
                self.view.makeToast(message, duration: 1.5, position: .center, style: style)
            })
            .disposed(by: disposeBag)

        output.schedulingSucceeded
            .emit(onNext: { [weak self] in
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                    self?.dismiss(animated: true)
                }
            })
            .disposed(by: disposeBag)

        tableView.rx.itemSelected
            .subscribe(onNext: { [weak self] indexPath in
                guard let self else { return }
                self.selectedPeriodRelay.accept(indexPath.row)
                self.tableView.reloadData()
            })
            .disposed(by: disposeBag)
    }
}

// MARK: - UITableViewDataSource

extension RemindNotificationViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        periodNames.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "PeriodCell", for: indexPath)

        var config = cell.defaultContentConfiguration()
        config.text = periodNames[indexPath.row]
        config.textProperties.font = UIFont(name: "GowunBatang-Regular", size: 16)
            ?? .systemFont(ofSize: 16)
        config.textProperties.color = .accent

        cell.contentConfiguration = config
        cell.backgroundColor = .clear
        cell.selectionStyle = .none
        cell.accessoryType = selectedPeriodRelay.value == indexPath.row ? .checkmark : .none
        cell.tintColor = .appPrimary

        return cell
    }
}
