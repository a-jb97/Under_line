//
//  HeatmapCardView.swift
//  Under_line
//

import UIKit
import SnapKit
import RxSwift
import RxCocoa

// MARK: - HeatmapDay

struct HeatmapDay {
    let date: Date
    let intensity: Int        // 0 = 없음, 1–4 = 독서량 단계
    let isCurrentMonth: Bool
    let durationSeconds: Int  // 해당 날 총 독서 시간(초)
}

// MARK: - HeatmapCardView

final class HeatmapCardView: UIView {

    private var currentYear = Calendar.current.component(.year, from: Date())
    private var currentMonth = Calendar.current.component(.month, from: Date())
    private var allSessions: [ReadingSession] = []
    private let disposeBag = DisposeBag()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.text = "독서 시간"
        l.font = UIFont(name: "GoyangIlsan R", size: 18)
            ?? .systemFont(ofSize: 18, weight: .semibold)
        l.textColor = .accent
        return l
    }()

    private let prevButton: UIButton = {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        b.tintColor = UIColor(hex: "#5d4037").withAlphaComponent(0.5)
        return b
    }()

    private let nextButton: UIButton = {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: "chevron.right"), for: .normal)
        b.tintColor = UIColor(hex: "#5d4037").withAlphaComponent(0.5)
        return b
    }()

    private let periodLabel: UILabel = {
        let l = UILabel()
        l.font = UIFont(name: "GoyangIlsan R", size: 13)
            ?? .systemFont(ofSize: 13)
        l.textColor = UIColor(hex: "#5d4037").withAlphaComponent(0.6)
        l.textAlignment = .center
        return l
    }()

    private let heatmapBody = HeatmapBodyView()

    private let legendStack: UIStackView = {
        let s = UIStackView()
        s.axis = .horizontal
        s.spacing = 4
        s.alignment = .center
        return s
    }()

    private let tooltipView: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor(hex: "#5d4037").withAlphaComponent(0.92)
        v.layer.cornerRadius = 8
        v.alpha = 0
        v.isUserInteractionEnabled = false
        return v
    }()

    private let tooltipLabel: UILabel = {
        let l = UILabel()
        l.font = UIFont(name: "GoyangIlsan R", size: 12) ?? .systemFont(ofSize: 12)
        l.textColor = .white
        return l
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        backgroundColor = .white
        layer.cornerRadius = 16
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = Float(CGFloat(0x26) / 255)
        layer.shadowRadius = 12
        layer.shadowOffset = CGSize(width: 0, height: 8)

        updatePeriodLabel()

        prevButton.rx.tap
            .subscribe(onNext: { [weak self] in
                guard let self else { return }
                self.clearSelection()
                self.currentMonth -= 1
                if self.currentMonth == 0 { self.currentMonth = 12; self.currentYear -= 1 }
                self.updatePeriodLabel()
                self.reloadHeatmap()
            })
            .disposed(by: disposeBag)

        nextButton.rx.tap
            .subscribe(onNext: { [weak self] in
                guard let self else { return }
                self.clearSelection()
                self.currentMonth += 1
                if self.currentMonth == 13 { self.currentMonth = 1; self.currentYear += 1 }
                self.updatePeriodLabel()
                self.reloadHeatmap()
            })
            .disposed(by: disposeBag)

        let periodTap = UITapGestureRecognizer()
        periodLabel.isUserInteractionEnabled = true
        periodLabel.addGestureRecognizer(periodTap)
        periodTap.rx.event
            .subscribe(onNext: { [weak self] _ in self?.showPeriodPicker() })
            .disposed(by: disposeBag)

        reloadHeatmap()

        // 타이틀 행: 좌측 "독서량", 우측 "< 2026년 X월 >"
        let titleRow = UIView()
        titleRow.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { $0.leading.top.bottom.equalToSuperview() }

        let navStack = UIStackView(arrangedSubviews: [prevButton, periodLabel, nextButton])
        navStack.axis = .horizontal
        navStack.spacing = 6
        navStack.alignment = .center
        prevButton.snp.makeConstraints { $0.size.equalTo(20) }
        nextButton.snp.makeConstraints { $0.size.equalTo(20) }

        titleRow.addSubview(navStack)
        navStack.snp.makeConstraints { make in
            make.trailing.top.bottom.equalToSuperview()
        }

        buildLegend()

        let vStack = UIStackView(arrangedSubviews: [titleRow, heatmapBody, legendStack])
        vStack.axis = .vertical
        vStack.spacing = 16

        addSubview(vStack)
        vStack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(20)
        }

        // 툴팁 설정
        tooltipView.addSubview(tooltipLabel)
        addSubview(tooltipView)

        heatmapBody.cellTapped
            .subscribe(onNext: { [weak self] (day, buttonFrame) in
                guard let self else { return }
                if let day {
                    self.showTooltip(for: day, buttonFrame: buttonFrame)
                } else {
                    self.hideTooltip()
                }
            })
            .disposed(by: disposeBag)
    }

    private func updatePeriodLabel() {
        periodLabel.text = "\(currentYear)년 \(currentMonth)월"
    }

    private func showPeriodPicker() {
        guard let vc = findViewController() else { return }
        let picker = MonthYearPickerViewController(year: currentYear, month: currentMonth)
        picker.onConfirm = { [weak self] year, month in
            self?.currentYear = year
            self?.currentMonth = month
            self?.updatePeriodLabel()
            self?.reloadHeatmap()
        }
        picker.modalPresentationStyle = .pageSheet
        if let sheet = picker.sheetPresentationController {
            sheet.detents = [.custom { _ in 290 }]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 20
        }
        vc.present(picker, animated: true)
    }

    private func findViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let r = responder {
            if let vc = r as? UIViewController { return vc }
            responder = r.next
        }
        return nil
    }

    func configure(with sessions: [ReadingSession]) {
        allSessions = sessions
        reloadHeatmap()
    }

    private func reloadHeatmap() {
        heatmapBody.days = buildGrid()
    }

    private func buildGrid() -> [[HeatmapDay]] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")

        // 날짜별 독서 시간 합산
        var durationByDay: [Date: Int] = [:]
        for session in allSessions {
            let dayStart = calendar.startOfDay(for: session.date)
            durationByDay[dayStart, default: 0] += session.durationSeconds
        }

        // 전월 1일 계산
        var prevMonth = currentMonth - 1
        var prevYear = currentYear
        if prevMonth == 0 { prevMonth = 12; prevYear -= 1 }

        guard let prevMonthFirstDay = calendar.date(
            from: DateComponents(year: prevYear, month: prevMonth, day: 1)
        ) else { return [] }

        // 전월 1일이 속한 주의 월요일 → 그리드 시작일
        // weekday: 1=일, 2=월, 3=화, ... 7=토
        let weekday = calendar.component(.weekday, from: prevMonthFirstDay)
        let mondayOffset = weekday == 1 ? -6 : -(weekday - 2)
        guard let gridStart = calendar.date(
            byAdding: .day, value: mondayOffset, to: prevMonthFirstDay
        ) else { return [] }

        // 7행(요일) × 11열(주) 그리드 생성
        var grid: [[HeatmapDay]] = Array(repeating: [], count: 7)
        for col in 0..<11 {
            for row in 0..<7 {
                let offset = col * 7 + row
                guard let date = calendar.date(byAdding: .day, value: offset, to: gridStart) else { continue }
                let dayStart = calendar.startOfDay(for: date)
                let duration = durationByDay[dayStart] ?? 0
                let intensity = Self.intensityLevel(seconds: duration)
                let comps = calendar.dateComponents([.year, .month], from: date)
                let isCurrentMonth = comps.year == currentYear && comps.month == currentMonth
                grid[row].append(HeatmapDay(date: date, intensity: intensity, isCurrentMonth: isCurrentMonth, durationSeconds: duration))
            }
        }
        return grid
    }

    private static func intensityLevel(seconds: Int) -> Int {
        switch seconds {
        case 0:            return 0
        case 1...600:      return 1
        case 601...1800:   return 2
        case 1801...3600:  return 3
        default:           return 4
        }
    }

    private func buildLegend() {
        let lessLabel = UILabel()
        lessLabel.text = "적음"
        lessLabel.font = .systemFont(ofSize: 10)
        lessLabel.textColor = UIColor(hex: "#5d4037", alpha: CGFloat(0x66) / 255)

        let moreLabel = UILabel()
        moreLabel.text = "많음"
        moreLabel.font = .systemFont(ofSize: 10)
        moreLabel.textColor = UIColor(hex: "#5d4037", alpha: CGFloat(0x66) / 255)

        let alphas: [CGFloat] = [
            CGFloat(0x0A) / 255,
            CGFloat(0x30) / 255,
            CGFloat(0x60) / 255,
            CGFloat(0xA0) / 255,
            1.0
        ]

        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        legendStack.addArrangedSubview(spacer)
        legendStack.addArrangedSubview(lessLabel)
        for a in alphas {
            let dot = UIView()
            dot.backgroundColor = UIColor(hex: "#5d4037", alpha: a)
            dot.layer.cornerRadius = 3
            dot.snp.makeConstraints { $0.size.equalTo(12) }
            legendStack.addArrangedSubview(dot)
        }
        legendStack.addArrangedSubview(moreLabel)
    }

    // MARK: - Tooltip

    private func showTooltip(for day: HeatmapDay, buttonFrame: CGRect) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일"
        let dateStr = formatter.string(from: day.date)

        let minutes = day.durationSeconds / 60
        let durationStr: String
        if day.durationSeconds == 0 {
            durationStr = "독서 없음"
        } else if minutes < 1 {
            durationStr = "1분 미만"
        } else {
            durationStr = "\(minutes)분 독서"
        }

        tooltipLabel.text = "\(dateStr) · \(durationStr)"
        tooltipLabel.sizeToFit()

        let hPad: CGFloat = 10
        let vPad: CGFloat = 6
        let tooltipW = tooltipLabel.frame.width + hPad * 2
        let tooltipH = tooltipLabel.frame.height + vPad * 2

        let btnRect = heatmapBody.convert(buttonFrame, to: self)
        var tx = btnRect.midX - tooltipW / 2
        tx = max(20, min(tx, bounds.width - tooltipW - 20))

        let gap: CGFloat = 6
        let ty: CGFloat = btnRect.minY > tooltipH + gap
            ? btnRect.minY - tooltipH - gap
            : btnRect.maxY + gap

        tooltipView.frame = CGRect(x: tx, y: ty, width: tooltipW, height: tooltipH)
        tooltipLabel.frame = CGRect(x: hPad, y: vPad,
                                    width: tooltipLabel.frame.width,
                                    height: tooltipLabel.frame.height)
        UIView.animate(withDuration: 0.15) { self.tooltipView.alpha = 1 }
    }

    private func hideTooltip() {
        UIView.animate(withDuration: 0.15) { self.tooltipView.alpha = 0 }
    }

    // MARK: - Tutorial Demo

    /// 튜토리얼용: 셀을 선택 상태로 만들고 툴팁을 표시합니다.
    func showDemoSelection() {
        guard let (day, buttonFrame) = heatmapBody.selectDemoCell() else { return }
        showTooltip(for: day, buttonFrame: buttonFrame)
    }

    /// 튜토리얼 종료 후 데모 선택 상태와 툴팁을 초기화합니다.
    func hideDemoSelection() {
        heatmapBody.deselectDemo()
        hideTooltip()
    }

    /// 현재 선택된 셀과 툴팁을 초기화합니다.
    func clearSelection() {
        heatmapBody.deselectDemo()
        hideTooltip()
    }
}

// MARK: - HeatmapBodyView

final class HeatmapBodyView: UIView {

    private static let cols = 11
    private static let rows = 7
    private static let gap: CGFloat = 4
    private static let labelWidth: CGFloat = 18
    private static let labelGridGap: CGFloat = 6

    private let weekdayLabels = ["월", "화", "수", "목", "금", "토", "일"]
    private let walnut = UIColor(hex: "#5d4037")

    var days: [[HeatmapDay]] = [] { didSet { needsRebuild = true; setNeedsLayout() } }

    private var cellButtons: [[UIButton]] = []
    private var selectedCell: (row: Int, col: Int)?
    private var lastWidth: CGFloat = 0
    private var needsRebuild = false
    private var cellDisposeBag = DisposeBag()

    private let cellTapSubject = PublishSubject<(day: HeatmapDay?, buttonFrame: CGRect)>()
    var cellTapped: Observable<(day: HeatmapDay?, buttonFrame: CGRect)> {
        cellTapSubject.asObservable()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: CGSize {
        let w = bounds.width > 0 ? bounds.width : 300
        let gridW = w - Self.labelWidth - Self.labelGridGap
        let cellSize = (gridW - CGFloat(Self.cols - 1) * Self.gap) / CGFloat(Self.cols)
        let h = CGFloat(Self.rows) * cellSize + CGFloat(Self.rows - 1) * Self.gap
        return CGSize(width: UIView.noIntrinsicMetric, height: max(h, 0))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { return }
        if abs(bounds.width - lastWidth) > 0.5 || needsRebuild {
            lastWidth = bounds.width
            needsRebuild = false
            buildCells()
            invalidateIntrinsicContentSize()
        }
    }

    private func buildCells() {
        subviews.forEach { $0.removeFromSuperview() }
        cellButtons = []

        let gridW = bounds.width - Self.labelWidth - Self.labelGridGap
        let cellSize = (gridW - CGFloat(Self.cols - 1) * Self.gap) / CGFloat(Self.cols)
        let gridX = Self.labelWidth + Self.labelGridGap

        let alphas: [CGFloat] = [
            CGFloat(0x0A) / 255,
            CGFloat(0x30) / 255,
            CGFloat(0x60) / 255,
            CGFloat(0xA0) / 255,
            1.0
        ]

        // 요일 레이블 (월 ~ 일)
        for (i, day) in weekdayLabels.enumerated() {
            let lbl = UILabel()
            lbl.text = day
            lbl.font = UIFont(name: "GoyangIlsan R", size: 11) ?? .systemFont(ofSize: 11)
            lbl.textColor = walnut.withAlphaComponent(0.5)
            lbl.textAlignment = .right
            lbl.sizeToFit()
            let cy = CGFloat(i) * (cellSize + Self.gap) + cellSize / 2
            lbl.frame = CGRect(
                x: Self.labelWidth - lbl.frame.width - 2,
                y: cy - lbl.frame.height / 2,
                width: lbl.frame.width,
                height: lbl.frame.height
            )
            addSubview(lbl)
        }

        // 그리드 셀 (정방형)
        for r in 0..<Self.rows {
            var row: [UIButton] = []
            for c in 0..<Self.cols {
                let btn = UIButton()
                let x = gridX + CGFloat(c) * (cellSize + Self.gap)
                let y = CGFloat(r) * (cellSize + Self.gap)
                btn.frame = CGRect(x: x, y: y, width: cellSize, height: cellSize)
                btn.layer.cornerRadius = 5

                let day = (r < days.count && c < days[r].count) ? days[r][c] : nil
                let level = day?.intensity ?? 0
                let baseAlpha = alphas[min(level, alphas.count - 1)]
                let alpha = (day?.isCurrentMonth ?? true) ? baseAlpha : baseAlpha * 0.35
                btn.backgroundColor = walnut.withAlphaComponent(alpha)

                addSubview(btn)
                row.append(btn)
            }
            cellButtons.append(row)
        }

        // rx.tap 구독
        cellDisposeBag = DisposeBag()
        for r in 0..<cellButtons.count {
            for c in 0..<cellButtons[r].count {
                let btn = cellButtons[r][c]
                btn.rx.tap
                    .subscribe(onNext: { [weak self] in
                        self?.handleCellTap(row: r, col: c, button: btn)
                    })
                    .disposed(by: cellDisposeBag)
            }
        }

        applySelection()
    }

    private func handleCellTap(row: Int, col: Int, button: UIButton) {
        let wasSame = selectedCell?.row == row && selectedCell?.col == col
        selectedCell = wasSame ? nil : (row, col)
        applySelection()

        if let (sr, sc) = selectedCell,
           sr < days.count, sc < days[sr].count {
            cellTapSubject.onNext((day: days[sr][sc], buttonFrame: button.frame))
        } else {
            cellTapSubject.onNext((day: nil, buttonFrame: .zero))
        }
    }

    private func applySelection() {
        for (r, row) in cellButtons.enumerated() {
            for (c, btn) in row.enumerated() {
                let isSelected = selectedCell?.row == r && selectedCell?.col == c
                btn.layer.borderColor = isSelected ? walnut.cgColor : UIColor.clear.cgColor
                btn.layer.borderWidth = isSelected ? 2 : 0
            }
        }
    }

    // MARK: - Tutorial Demo

    /// 튜토리얼용: 데이터가 있는 셀(없으면 중간 셀)을 선택 상태로 만들고 결과를 반환합니다.
    func selectDemoCell() -> (day: HeatmapDay, buttonFrame: CGRect)? {
        var demoRow: Int?
        var demoCol: Int?

        // 오른쪽 열(최근)부터 독서 기록이 있는 셀 탐색
        let numCols = days.first?.count ?? 0
        outer: for c in stride(from: numCols - 1, through: 0, by: -1) {
            for r in 0..<days.count {
                guard c < days[r].count, days[r][c].durationSeconds > 0,
                      r < cellButtons.count, c < cellButtons[r].count else { continue }
                demoRow = r; demoCol = c
                break outer
            }
        }

        // 기록 없으면 그리드 중간 셀 fallback
        if demoRow == nil {
            let midRow = min(3, max(0, cellButtons.count - 1))
            let midCol = min(6, max(0, (cellButtons.first?.count ?? 1) - 1))
            if midRow < cellButtons.count, midCol < cellButtons[midRow].count {
                demoRow = midRow; demoCol = midCol
            }
        }

        guard let r = demoRow, let c = demoCol,
              r < cellButtons.count, c < cellButtons[r].count else { return nil }

        selectedCell = (row: r, col: c)
        applySelection()

        let day = (r < days.count && c < days[r].count)
            ? days[r][c]
            : HeatmapDay(date: Date(), intensity: 0, isCurrentMonth: true, durationSeconds: 0)

        return (day: day, buttonFrame: cellButtons[r][c].frame)
    }

    func deselectDemo() {
        selectedCell = nil
        applySelection()
    }
}

// MARK: - MonthYearPickerViewController

final class MonthYearPickerViewController: UIViewController,
                                            UIPickerViewDataSource,
                                            UIPickerViewDelegate {

    var onConfirm: ((Int, Int) -> Void)?

    private let years: [Int]
    private let monthNames = (1...12).map { "\($0)월" }
    private var selectedYear: Int
    private var selectedMonth: Int
    private let nowYear: Int
    private let nowMonth: Int

    private let picker = UIPickerView()
    private let confirmButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("확인", for: .normal)
        btn.titleLabel?.font = UIFont(name: "GoyangIlsan R", size: 15)
            ?? .systemFont(ofSize: 15, weight: .semibold)
        btn.tintColor = .accent
        return btn
    }()
    private let disposeBag = DisposeBag()

    init(year: Int, month: Int) {
        let cal = Calendar.current
        let today = Date()
        nowYear  = cal.component(.year,  from: today)
        nowMonth = cal.component(.month, from: today)
        self.years = Array((nowYear - 10)...nowYear)
        self.selectedYear  = min(year, nowYear)
        self.selectedMonth = (year == nowYear) ? min(month, nowMonth) : month
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .background

        let titleLabel = UILabel()
        titleLabel.text = "날짜 선택"
        titleLabel.font = UIFont(name: "GoyangIlsan R", size: 17)
            ?? .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .accent

        confirmButton.rx.tap
            .subscribe(onNext: { [weak self] in
                guard let self else { return }
                self.onConfirm?(self.selectedYear, self.selectedMonth)
                self.dismiss(animated: true)
            })
            .disposed(by: disposeBag)

        picker.dataSource = self
        picker.delegate = self

        if let yearIdx = years.firstIndex(of: selectedYear) {
            picker.selectRow(yearIdx, inComponent: 0, animated: false)
        }
        picker.selectRow(selectedMonth - 1, inComponent: 1, animated: false)

        view.addSubview(titleLabel)
        view.addSubview(confirmButton)
        view.addSubview(picker)

        titleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.centerX.equalToSuperview()
        }
        confirmButton.snp.makeConstraints { make in
            make.centerY.equalTo(titleLabel)
            make.trailing.equalToSuperview().inset(24)
        }
        picker.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(-16)
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide).inset(8)
        }
    }

    // MARK: UIPickerViewDataSource

    func numberOfComponents(in pickerView: UIPickerView) -> Int { 2 }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        component == 0 ? years.count : 12
    }

    // MARK: UIPickerViewDelegate

    func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {
        let lbl = (view as? UILabel) ?? {
            let l = UILabel()
            l.textAlignment = .center
            l.font = UIFont(name: "GoyangIlsan R", size: 16) ?? .systemFont(ofSize: 16)
            l.isUserInteractionEnabled = false
            return l
        }()
        lbl.text = component == 0 ? "\(years[row])년" : monthNames[row]
        let isFuture: Bool
        if component == 0 {
            isFuture = years[row] > nowYear
        } else {
            isFuture = selectedYear == nowYear && (row + 1) > nowMonth
        }
        lbl.textColor = isFuture ? .tertiaryLabel : .appPrimary
        return lbl
    }

    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        if component == 0 {
            selectedYear = years[row]
            // 미래 연도 선택 차단: 현재 연도로 되돌림
            if selectedYear > nowYear {
                selectedYear = nowYear
                picker.selectRow(years.firstIndex(of: nowYear) ?? row, inComponent: 0, animated: true)
            }
            // 연도 변경 시 월 색상 업데이트
            picker.reloadComponent(1)
            // 선택된 월이 현재 연도에서 미래 월이면 이번 달로 조정
            if selectedYear == nowYear && selectedMonth > nowMonth {
                selectedMonth = nowMonth
                picker.selectRow(selectedMonth - 1, inComponent: 1, animated: true)
            }
        } else {
            let month = row + 1
            // 미래 월 선택 차단
            if selectedYear == nowYear && month > nowMonth {
                selectedMonth = nowMonth
                picker.selectRow(selectedMonth - 1, inComponent: 1, animated: true)
            } else {
                selectedMonth = month
            }
        }
    }
}
