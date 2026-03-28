//
//  ProgressSectionView.swift
//  Under_line
//
//  독서 진행률 카드 — BookDetailViewController 와 ReadingRecordViewController 공유
//

import UIKit
import SnapKit
import RxSwift
import RxCocoa

final class ProgressSectionView: UIView {

    // MARK: - Public

    var editButtonTap: Observable<Void> { editButton.rx.tap.asObservable() }

    // MARK: - Subviews

    private let progressHeaderLabel: UILabel = {
        let l = UILabel()
        let attrStr = NSMutableAttributedString(
            string: "독서 진행률 : ",
            attributes: [
                .font:            UIFont(name: "GoyangIlsan R", size: 13) ?? .systemFont(ofSize: 13),
                .foregroundColor: UIColor.accent,
            ]
        )
        attrStr.append(NSAttributedString(
            string: "0%",
            attributes: [
                .font:            UIFont(name: "GoyangIlsan R", size: 13) ?? .systemFont(ofSize: 13),
                .foregroundColor: UIColor.appPrimary,
            ]
        ))
        l.attributedText = attrStr
        return l
    }()

    private lazy var editButton: UIButton = {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 10, weight: .regular)
        btn.setImage(UIImage(systemName: "pencil", withConfiguration: cfg), for: .normal)
        btn.setTitle(" 편집", for: .normal)
        btn.titleLabel?.font = UIFont(name: "GoyangIlsan R", size: 12) ?? .systemFont(ofSize: 12)
        btn.tintColor = UIColor.appPrimary.withAlphaComponent(0.7)
        btn.setTitleColor(UIColor.appPrimary.withAlphaComponent(0.7), for: .normal)
        return btn
    }()

    private let progressBarBg: UIView = {
        let v = UIView()
        v.backgroundColor    = UIColor(hex: "#5d4037", alpha: CGFloat(0x20) / 255)
        v.layer.cornerRadius = 6
        v.clipsToBounds      = true
        return v
    }()

    private let progressBarFill: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 4
        v.clipsToBounds      = true
        return v
    }()

    private let progressDetailLabel: UILabel = {
        let l = UILabel()
        l.text      = "0 / - 페이지"
        l.font      = UIFont(name: "GoyangIlsan R", size: 11) ?? .systemFont(ofSize: 11)
        l.textColor = UIColor.appPrimary.withAlphaComponent(0.45)
        return l
    }()

    private var gradientLayer: CAGradientLayer?

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
        setupConstraints()
        setupGradient()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer?.frame = progressBarFill.bounds
    }

    // MARK: - Private Setup

    private func setupView() {
        backgroundColor    = UIColor.background
        layer.cornerRadius = 12
        layer.shadowColor   = UIColor(hex: "#5d4037").cgColor
        layer.shadowOpacity = Float(CGFloat(0x25) / 255)
        layer.shadowRadius  = 2.5
        layer.shadowOffset  = CGSize(width: 3, height: 3)

        progressBarBg.addSubview(progressBarFill)
        addSubview(progressHeaderLabel)
        addSubview(editButton)
        addSubview(progressBarBg)
        addSubview(progressDetailLabel)
    }

    private func setupConstraints() {
        progressHeaderLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(14)
            make.top.equalToSuperview().inset(12)
        }
        editButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(14)
            make.centerY.equalTo(progressHeaderLabel)
        }
        progressBarBg.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(14)
            make.top.equalTo(progressHeaderLabel.snp.bottom).offset(10)
            make.height.equalTo(24)
        }
        progressBarFill.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
            make.width.equalToSuperview().multipliedBy(0)
        }
        progressDetailLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().inset(14)
            make.top.equalTo(progressBarBg.snp.bottom).offset(10)
            make.bottom.equalToSuperview().inset(12)
        }
    }

    private func setupGradient() {
        let grad = CAGradientLayer()
        grad.colors       = [UIColor.appPrimary.cgColor, UIColor(hex: "#8D6E63").cgColor]
        grad.startPoint   = CGPoint(x: 0, y: 0.5)
        grad.endPoint     = CGPoint(x: 1, y: 0.5)
        grad.cornerRadius = 4
        progressBarFill.layer.addSublayer(grad)
        gradientLayer = grad
    }

    // MARK: - Public

    func configure(currentPage: Int, itemPage: Int) {
        let ratio   = CGFloat(currentPage) / CGFloat(itemPage)
        let percent = Int(ratio * 100)

        progressDetailLabel.text = "\(currentPage) / \(itemPage) 페이지"

        let attrStr = NSMutableAttributedString(
            string: "독서 진행률 : ",
            attributes: [
                .font:            UIFont(name: "GoyangIlsan R", size: 13) ?? .systemFont(ofSize: 13),
                .foregroundColor: UIColor.accent,
            ]
        )
        attrStr.append(NSAttributedString(
            string: "\(percent)%",
            attributes: [
                .font:            UIFont(name: "GoyangIlsan R", size: 13) ?? .systemFont(ofSize: 13),
                .foregroundColor: UIColor.appPrimary,
            ]
        ))
        progressHeaderLabel.attributedText = attrStr

        progressBarFill.snp.remakeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
            make.width.equalToSuperview().multipliedBy(ratio)
        }
        UIView.animate(withDuration: 0.4) {
            self.progressBarBg.layoutIfNeeded()
        }
    }

    func showNoProgress(itemPage: Int) {
        progressDetailLabel.text = "0 / \(itemPage) 페이지"
    }
}
