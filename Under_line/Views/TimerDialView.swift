//
//  TimerDialView.swift
//  Under_line
//
//  뽀모도로 타이머 다이얼 뷰 — ReadingRecordViewController에서 분리
//

import UIKit
import SnapKit
import AVFoundation
import AudioToolbox

final class TimerDialView: UIView {

    // MARK: - Callbacks
    var onTimerStateChanged: ((Bool) -> Void)?   // isRunning 변화 시 호출
    var onTimerStopped: ((Int) -> Void)?         // 정지/완료 시 경과 초(elapsed seconds) 전달

    // MARK: - Timer State
    private(set) var setMinutes: Int = 0
    private(set) var remainingSeconds: Int = 0
    private var accumulatedSeconds = 0
    private var sessionStartRemainingSeconds = 0
    private let dialHaptic = UIImpactFeedbackGenerator(style: .light)
    private(set) var isRunning = false
    private var countdownTimer: Timer?
    private var timerEndDate: Date?
    private var didSetupDial = false
    private var dialPreviousAngle: CGFloat?
    private var gradientLayers: [(view: UIView, layer: CAGradientLayer)] = []

    // MARK: - Dial
    private let dialContainer: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor(hex: "#E8E0DC")
        v.layer.cornerRadius = 130
        v.layer.shadowColor   = UIColor.black.cgColor
        v.layer.shadowOpacity = Float(CGFloat(0x25) / 255)
        v.layer.shadowRadius  = 8
        v.layer.shadowOffset  = CGSize(width: 4, height: 4)
        return v
    }()

    private let outerWedgeLayer = CAShapeLayer()
    private let innerArcLayer   = CAShapeLayer()

    private let markingsView: UIView = {
        let v = UIView()
        v.backgroundColor = .clear
        v.isUserInteractionEnabled = false
        return v
    }()

    private let dialFaceView: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor(hex: "#f6efee")
        v.layer.cornerRadius = 130
        return v
    }()

    private let innerCircleLightShadow: UIView = {
        let v = UIView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = .white
        v.layer.cornerRadius = 83.2
        v.layer.shadowColor   = UIColor.white.cgColor
        v.layer.shadowOpacity = 1.0
        v.layer.shadowRadius  = 12
        v.layer.shadowOffset  = CGSize(width: -6, height: -6)
        return v
    }()

    private let innerCircleView: UIView = {
        let v = UIView()
        v.backgroundColor = .white
        v.layer.cornerRadius = 83.2
        v.layer.shadowColor   = UIColor(hex: "#C5BDB8").cgColor
        v.layer.shadowOpacity = 1.0
        v.layer.shadowRadius  = 12
        v.layer.shadowOffset  = CGSize(width: 6, height: 6)
        return v
    }()

    private let centerKnobView: UIView = {
        let v = UIView()
        v.backgroundColor   = UIColor(hex: "#E8E0DC")
        v.layer.cornerRadius = 15.6
        v.layer.shadowColor   = UIColor.black.cgColor
        v.layer.shadowOpacity = Float(CGFloat(0x22) / 255)
        v.layer.shadowRadius  = 8
        v.layer.shadowOffset  = CGSize(width: 4, height: 4)
        return v
    }()

    // MARK: - Neumorphism Shadow Views

    private let dialContainerLightShadow: UIView = {
        let v = UIView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = UIColor(hex: "#E8E0DC")
        v.layer.cornerRadius = 130
        v.layer.shadowColor   = UIColor.white.cgColor
        v.layer.shadowOpacity = Float(CGFloat(0x90) / 255)
        v.layer.shadowRadius  = 8
        v.layer.shadowOffset  = CGSize(width: -4, height: -4)
        return v
    }()

    private let dialFaceDarkShadow: UIView = {
        let v = UIView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = UIColor(hex: "#f6efee")
        v.layer.cornerRadius = 130
        v.layer.shadowColor   = UIColor.black.cgColor
        v.layer.shadowOpacity = Float(CGFloat(0x18) / 255)
        v.layer.shadowRadius  = 6
        v.layer.shadowOffset  = CGSize(width: 3, height: 3)
        return v
    }()

    private let dialFaceLightShadow: UIView = {
        let v = UIView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = UIColor(hex: "#f6efee")
        v.layer.cornerRadius = 130
        v.layer.shadowColor   = UIColor.white.cgColor
        v.layer.shadowOpacity = Float(CGFloat(0x80) / 255)
        v.layer.shadowRadius  = 6
        v.layer.shadowOffset  = CGSize(width: -3, height: -3)
        return v
    }()

    private let innerCircleSmallDarkShadow: UIView = {
        let v = UIView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = .white
        v.layer.cornerRadius = 83.2
        v.layer.shadowColor   = UIColor(hex: "#C5BDB8").cgColor
        v.layer.shadowOpacity = Float(CGFloat(0x30) / 255)
        v.layer.shadowRadius  = 4
        v.layer.shadowOffset  = CGSize(width: 2, height: 2)
        return v
    }()

    private let innerCircleSmallLightShadow: UIView = {
        let v = UIView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = .white
        v.layer.cornerRadius = 83.2
        v.layer.shadowColor   = UIColor.white.cgColor
        v.layer.shadowOpacity = Float(CGFloat(0x90) / 255)
        v.layer.shadowRadius  = 4
        v.layer.shadowOffset  = CGSize(width: -2, height: -2)
        return v
    }()

    private let centerKnobLightShadow: UIView = {
        let v = UIView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = UIColor(hex: "#E8E0DC")
        v.layer.cornerRadius = 15.6
        v.layer.shadowColor   = UIColor.white.cgColor
        v.layer.shadowOpacity = Float(CGFloat(0x90) / 255)
        v.layer.shadowRadius  = 8
        v.layer.shadowOffset  = CGSize(width: -4, height: -4)
        return v
    }()

    private let centerKnobSmallDarkShadow: UIView = {
        let v = UIView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = UIColor(hex: "#E8E0DC")
        v.layer.cornerRadius = 15.6
        v.layer.shadowColor   = UIColor.black.cgColor
        v.layer.shadowOpacity = Float(CGFloat(0x12) / 255)
        v.layer.shadowRadius  = 2
        v.layer.shadowOffset  = CGSize(width: 1, height: 1)
        return v
    }()

    private let centerKnobSmallLightShadow: UIView = {
        let v = UIView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = UIColor(hex: "#E8E0DC")
        v.layer.cornerRadius = 15.6
        v.layer.shadowColor   = UIColor.white.cgColor
        v.layer.shadowOpacity = Float(CGFloat(0x70) / 255)
        v.layer.shadowRadius  = 2
        v.layer.shadowOffset  = CGSize(width: -1, height: -1)
        return v
    }()

    private let knobNeedleView: UIView = {
        let v = UIView()
        v.backgroundColor    = UIColor.appPrimary
        v.layer.cornerRadius = 1
        return v
    }()

    // MARK: - Timer Text
    private let timerLabel: UILabel = {
        let l = UILabel()
        l.text = "00 : 00"
        l.font = UIFont(name: "GoyangIlsan R", size: 24)
            ?? .systemFont(ofSize: 24, weight: .light)
        l.textColor   = UIColor.appPrimary
        l.textAlignment = .center
        return l
    }()

    // MARK: - Controls
    private lazy var resetButton: UIButton = {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        btn.setImage(UIImage(systemName: "arrow.counterclockwise", withConfiguration: cfg), for: .normal)
        btn.tintColor        = UIColor.appPrimary.withAlphaComponent(0.6)
        btn.backgroundColor  = UIColor(hex: "#5d4037", alpha: CGFloat(0x12) / 255)
        btn.layer.cornerRadius = 22
        btn.layer.borderWidth  = 1
        btn.layer.borderColor  = UIColor(hex: "#5d4037", alpha: CGFloat(0x15) / 255).cgColor
        return btn
    }()

    private lazy var playButton: UIButton = {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        btn.setImage(UIImage(systemName: "play.fill", withConfiguration: cfg), for: .normal)
        btn.tintColor          = UIColor.appPrimary
        btn.layer.cornerRadius = 28
        btn.clipsToBounds      = true
        return btn
    }()

    private lazy var stopButton: UIButton = {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        btn.setImage(UIImage(systemName: "stop.fill", withConfiguration: cfg), for: .normal)
        btn.tintColor        = UIColor.appPrimary.withAlphaComponent(0.6)
        btn.backgroundColor  = UIColor(hex: "#5d4037", alpha: CGFloat(0x12) / 255)
        btn.layer.cornerRadius = 22
        btn.layer.borderWidth  = 1
        btn.layer.borderColor  = UIColor(hex: "#5d4037", alpha: CGFloat(0x15) / 255).cgColor
        return btn
    }()

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        setupConstraints()
        setupBackgroundObservers()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        for (view, gradient) in gradientLayers {
            gradient.frame = view.bounds
        }
        if dialContainer.bounds.width > 0 { drawTimerDial() }
    }

    // MARK: - Setup

    private func setupUI() {
        dialContainer.addSubview(dialFaceLightShadow)
        dialContainer.addSubview(dialFaceDarkShadow)
        dialContainer.addSubview(dialFaceView)
        dialContainer.layer.addSublayer(outerWedgeLayer)
        dialContainer.addSubview(markingsView)
        dialContainer.addSubview(innerCircleSmallLightShadow)
        dialContainer.addSubview(innerCircleSmallDarkShadow)
        dialContainer.addSubview(innerCircleLightShadow)
        dialContainer.addSubview(innerCircleView)
        dialContainer.layer.addSublayer(innerArcLayer)
        centerKnobView.addSubview(knobNeedleView)
        knobNeedleView.transform = CGAffineTransform(rotationAngle: -.pi / 2)
        dialContainer.addSubview(centerKnobSmallDarkShadow)
        dialContainer.addSubview(centerKnobSmallLightShadow)
        dialContainer.addSubview(centerKnobLightShadow)
        dialContainer.addSubview(centerKnobView)
        addSubview(dialContainerLightShadow)
        addSubview(dialContainer)

        addSubview(timerLabel)
        addSubview(resetButton)
        addSubview(playButton)
        addSubview(stopButton)

        applyGlassStyle(to: playButton, cornerRadius: 28)

        resetButton.addTarget(self, action: #selector(resetTapped), for: .touchUpInside)
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        stopButton.addTarget(self, action: #selector(stopTapped), for: .touchUpInside)
    }

    private func setupConstraints() {
        dialContainerLightShadow.snp.makeConstraints { make in
            make.edges.equalTo(dialContainer)
        }
        dialContainer.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview()
            make.size.equalTo(260)
        }
        dialFaceLightShadow.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        dialFaceDarkShadow.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        dialFaceView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        markingsView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        innerCircleSmallLightShadow.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(CGFloat(166.4))
        }
        innerCircleSmallDarkShadow.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(CGFloat(166.4))
        }
        innerCircleLightShadow.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(CGFloat(166.4))
        }
        innerCircleView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(CGFloat(166.4))
        }
        centerKnobSmallDarkShadow.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(CGFloat(31.2))
        }
        centerKnobSmallLightShadow.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(CGFloat(31.2))
        }
        centerKnobLightShadow.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(CGFloat(31.2))
        }
        centerKnobView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(CGFloat(31.2))
        }
        knobNeedleView.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.trailing.equalToSuperview().inset(4)
            make.width.equalTo(CGFloat(1.95))
            make.height.equalTo(CGFloat(10.4))
        }

        timerLabel.snp.makeConstraints { make in
            make.top.equalTo(dialContainer.snp.bottom).offset(20)
            make.centerX.equalToSuperview()
        }
        playButton.snp.makeConstraints { make in
            make.top.equalTo(timerLabel.snp.bottom).offset(16)
            make.centerX.equalToSuperview()
            make.size.equalTo(56)
            make.bottom.equalToSuperview()
        }
        resetButton.snp.makeConstraints { make in
            make.trailing.equalTo(playButton.snp.leading).offset(-16)
            make.centerY.equalTo(playButton)
            make.size.equalTo(44)
        }
        stopButton.snp.makeConstraints { make in
            make.leading.equalTo(playButton.snp.trailing).offset(16)
            make.centerY.equalTo(playButton)
            make.size.equalTo(44)
        }
    }

    // MARK: - Dial Drawing

    private func drawTimerDial() {
        guard !didSetupDial else { return }
        didSetupDial = true

        updateDialArc(fraction: 0.0)
        addTickMarks()
        addDialLabels()
        setupDialGesture()
        updateNeedle(minutes: 0)
    }

    private func updateDialArc(fraction: CGFloat) {
        let center = CGPoint(x: 130, y: 130)
        let endAngle = -.pi / 2 + fraction * 2 * .pi

        if fraction <= 0 {
            outerWedgeLayer.path = nil
            innerArcLayer.path   = nil
            return
        }

        let outerPath = UIBezierPath()
        outerPath.move(to: center)
        outerPath.addArc(withCenter: center, radius: 122.2,
                         startAngle: -.pi / 2, endAngle: endAngle, clockwise: true)
        outerPath.close()
        outerWedgeLayer.path      = outerPath.cgPath
        outerWedgeLayer.fillColor = UIColor(hex: "#DDD4CE").withAlphaComponent(0.5).cgColor

        let innerPath = UIBezierPath()
        innerPath.move(to: center)
        innerPath.addArc(withCenter: center, radius: 83.2,
                         startAngle: -.pi / 2, endAngle: endAngle, clockwise: true)
        innerPath.close()
        innerArcLayer.path      = innerPath.cgPath
        innerArcLayer.fillColor = UIColor.appPrimary.withAlphaComponent(0.9).cgColor
    }

    private func updateNeedle(minutes: Int) {
        let rotation = CGFloat(minutes) / 60.0 * 2 * .pi - .pi / 2
        centerKnobView.transform = CGAffineTransform(rotationAngle: rotation)
    }

    private func setupDialGesture() {
        dialHaptic.prepare()
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleDialPan(_:)))
        dialContainer.addGestureRecognizer(pan)
    }

    @objc private func handleDialPan(_ gesture: UIPanGestureRecognizer) {
        guard !isRunning else { return }

        let loc    = gesture.location(in: dialContainer)
        let center = CGPoint(x: 130, y: 130)

        var angle = atan2(loc.y - center.y, loc.x - center.x) + .pi / 2
        if angle < 0 { angle += 2 * .pi }

        if gesture.state == .began {
            dialPreviousAngle = angle
            return
        }
        if gesture.state == .ended || gesture.state == .cancelled {
            dialPreviousAngle = nil
            return
        }

        guard let prevAngle = dialPreviousAngle else {
            dialPreviousAngle = angle
            return
        }

        var delta = angle - prevAngle
        if delta >  .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }
        dialPreviousAngle = angle

        let isClockwise = delta > 0
        if !isClockwise && setMinutes == 0 { return }

        let rawMinutes = angle / (2 * .pi) * 60.0
        let snapped    = Int((rawMinutes / 5.0).rounded()) * 5
        let newMinutes = min(snapped, 60)

        if isClockwise && setMinutes == 60 && newMinutes < setMinutes { return }
        guard newMinutes != setMinutes else { return }

        setMinutes = newMinutes
        dialHaptic.impactOccurred()
        remainingSeconds = setMinutes * 60
        updateTimerDisplay()
        updateDialArc(fraction: CGFloat(setMinutes) / 60.0)
        updateNeedle(minutes: setMinutes)
    }

    private func addTickMarks() {
        let center       = CGPoint(x: 130, y: 130)
        let outerRadius: CGFloat = 122.2
        let tickLength:  CGFloat = 10.4
        let tickWidth:   CGFloat = 1.95

        for i in 0..<12 {
            let angle = CGFloat(i) * (.pi * 2 / 12) - .pi / 2
            let outerPt = CGPoint(x: center.x + outerRadius * cos(angle),
                                  y: center.y + outerRadius * sin(angle))
            let innerPt = CGPoint(x: center.x + (outerRadius - tickLength) * cos(angle),
                                  y: center.y + (outerRadius - tickLength) * sin(angle))

            let path = UIBezierPath()
            path.move(to: innerPt)
            path.addLine(to: outerPt)

            let layer = CAShapeLayer()
            layer.path        = path.cgPath
            layer.strokeColor = UIColor.appPrimary.cgColor
            layer.lineWidth   = tickWidth
            layer.lineCap     = .round
            markingsView.layer.addSublayer(layer)
        }
    }

    private func addDialLabels() {
        let center      = CGPoint(x: 130, y: 130)
        let labelRadius: CGFloat = 100
        let minutes = [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55]

        for (i, minute) in minutes.enumerated() {
            let angle = CGFloat(i) * (.pi * 2 / 12) - .pi / 2
            let x = center.x + labelRadius * cos(angle)
            let y = center.y + labelRadius * sin(angle)

            let label = UILabel()
            label.text          = "\(minute)"
            label.font          = UIFont(name: "GoyangIlsan R", size: 11.7) ?? .systemFont(ofSize: 11.7)
            label.textColor     = UIColor.appPrimary
            label.textAlignment = .center
            label.sizeToFit()
            label.center = CGPoint(x: x, y: y)
            markingsView.addSubview(label)
        }
    }

    // MARK: - Button Actions

    @objc private func playTapped()  { toggleTimer() }
    @objc private func resetTapped() { resetTimer() }
    @objc private func stopTapped()  { stopTimer() }

    // MARK: - Timer Logic

    private func toggleTimer() {
        isRunning ? pauseTimer() : startTimer()
    }

    private func startTimer() {
        guard setMinutes > 0 else { return }
        sessionStartRemainingSeconds = remainingSeconds
        isRunning    = true
        timerEndDate = Date().addingTimeInterval(TimeInterval(remainingSeconds))
        let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        playButton.setImage(UIImage(systemName: "pause.fill", withConfiguration: cfg), for: .normal)
        scheduleCountdownTimer()
        onTimerStateChanged?(true)
    }

    private func scheduleCountdownTimer() {
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tickTimer()
        }
        RunLoop.current.add(countdownTimer!, forMode: .common)
    }

    private func pauseTimer() {
        if isRunning {
            accumulatedSeconds += sessionStartRemainingSeconds - remainingSeconds
        }
        isRunning    = false
        timerEndDate = nil
        let cfg = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        playButton.setImage(UIImage(systemName: "play.fill", withConfiguration: cfg), for: .normal)
        countdownTimer?.invalidate()
        countdownTimer = nil
        onTimerStateChanged?(false)
    }

    private func stopTimer() {
        let elapsed = accumulatedSeconds + (isRunning ? sessionStartRemainingSeconds - remainingSeconds : 0)
        pauseTimer()
        accumulatedSeconds = 0
        sessionStartRemainingSeconds = 0
        if elapsed > 0 { onTimerStopped?(elapsed) }
    }

    private func resetTimer() {
        pauseTimer()
        accumulatedSeconds = 0
        sessionStartRemainingSeconds = 0
        setMinutes       = 0
        remainingSeconds = 0
        updateTimerDisplay()
        updateDialArc(fraction: 0.0)
        updateNeedle(minutes: 0)
    }

    private func tickTimer() {
        guard let endDate = timerEndDate else { stopTimer(); return }
        let remaining = max(0, Int(endDate.timeIntervalSinceNow))
        guard remaining > 0 else {
            remainingSeconds = 0
            updateTimerDisplay()
            updateDialArc(fraction: 0)
            updateNeedle(minutes: 0)
            stopTimer()
            playAlarm()
            return
        }
        remainingSeconds = remaining
        updateTimerDisplay()
        updateDialArc(fraction: CGFloat(remaining) / 3600.0)
        updateNeedle(minutes: Int((CGFloat(remaining) / 60.0).rounded()))
    }

    private func updateTimerDisplay() {
        let m = remainingSeconds / 60
        let s = remainingSeconds % 60
        timerLabel.text = String(format: "%02d : %02d", m, s)
    }

    private func playAlarm() {
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        AudioServicesPlayAlertSound(SystemSoundID(1005))
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    // MARK: - Background Handling

    private func setupBackgroundObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    @objc private func appDidEnterBackground() {
        guard isRunning else { return }
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    @objc private func appWillEnterForeground() {
        guard isRunning, let endDate = timerEndDate else { return }
        let remaining = max(0, Int(endDate.timeIntervalSinceNow))
        if remaining <= 0 {
            remainingSeconds = 0
            updateTimerDisplay()
            updateDialArc(fraction: 0)
            updateNeedle(minutes: 0)
            stopTimer()
            playAlarm()
        } else {
            remainingSeconds = remaining
            updateTimerDisplay()
            updateDialArc(fraction: CGFloat(remaining) / 3600.0)
            updateNeedle(minutes: Int((CGFloat(remaining) / 60.0).rounded()))
            scheduleCountdownTimer()
        }
    }

    // MARK: - Glass Style

    private func applyGlassStyle(to button: UIButton, cornerRadius: CGFloat) {
        let shadowView = UIView()
        shadowView.isUserInteractionEnabled = false
        shadowView.layer.cornerRadius = cornerRadius
        shadowView.backgroundColor    = .white
        shadowView.layer.shadowColor   = UIColor.black.cgColor
        shadowView.layer.shadowOpacity = Float(CGFloat(0x18) / 255)
        shadowView.layer.shadowRadius  = 8
        shadowView.layer.shadowOffset  = CGSize(width: 0, height: 6)
        insertSubview(shadowView, belowSubview: button)
        shadowView.snp.makeConstraints { $0.edges.equalTo(button) }

        let glassContainer = UIView()
        glassContainer.isUserInteractionEnabled = false
        glassContainer.layer.cornerRadius = cornerRadius
        glassContainer.clipsToBounds      = true
        glassContainer.layer.borderWidth  = 1
        glassContainer.layer.borderColor  = UIColor(white: 1, alpha: CGFloat(0x70) / 255).cgColor
        insertSubview(glassContainer, belowSubview: button)
        glassContainer.snp.makeConstraints { $0.edges.equalTo(button) }
        insertSubview(shadowView, belowSubview: glassContainer)

        let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
        blurView.isUserInteractionEnabled = false
        glassContainer.addSubview(blurView)
        blurView.snp.makeConstraints { $0.edges.equalToSuperview() }

        let solidTint = UIView()
        solidTint.isUserInteractionEnabled = false
        solidTint.backgroundColor = UIColor(hex: "#832C11", alpha: CGFloat(0x24) / 255)
        blurView.contentView.addSubview(solidTint)
        solidTint.snp.makeConstraints { $0.edges.equalToSuperview() }

        let topSpecular = UIView()
        topSpecular.isUserInteractionEnabled = false
        blurView.contentView.addSubview(topSpecular)
        topSpecular.snp.makeConstraints { $0.edges.equalToSuperview() }
        let topGrad = CAGradientLayer()
        topGrad.colors     = [UIColor(white: 1, alpha: CGFloat(0x50) / 255).cgColor,
                               UIColor(white: 1, alpha: CGFloat(0x10) / 255).cgColor,
                               UIColor.clear.cgColor]
        topGrad.locations  = [0, 0.45, 1.0]
        topGrad.startPoint = CGPoint(x: 0.5, y: 0)
        topGrad.endPoint   = CGPoint(x: 0.5, y: 1)
        topSpecular.layer.addSublayer(topGrad)
        gradientLayers.append((topSpecular, topGrad))

        let bottomWarm = UIView()
        bottomWarm.isUserInteractionEnabled = false
        blurView.contentView.addSubview(bottomWarm)
        bottomWarm.snp.makeConstraints { $0.edges.equalToSuperview() }
        let bottomGrad = CAGradientLayer()
        bottomGrad.colors     = [UIColor(hex: "#832C11", alpha: CGFloat(0x20) / 255).cgColor,
                                  UIColor(hex: "#832C11", alpha: CGFloat(0x0C) / 255).cgColor,
                                  UIColor.clear.cgColor]
        bottomGrad.locations  = [0, 0.5, 1.0]
        bottomGrad.startPoint = CGPoint(x: 0.5, y: 1)
        bottomGrad.endPoint   = CGPoint(x: 0.5, y: 0)
        bottomWarm.layer.addSublayer(bottomGrad)
        gradientLayers.append((bottomWarm, bottomGrad))

        button.backgroundColor = .clear
    }
}
