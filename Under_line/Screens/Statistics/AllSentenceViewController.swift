//
//  AllSentenceViewController.swift
//  Under_line
//
//  저장된 모든 밑줄 모아보기 화면
//

import UIKit
import SnapKit
import RxSwift
import RxCocoa

final class AllSentenceViewController: UIViewController {

    private let disposeBag            = DisposeBag()
    private let viewWillAppearRelay   = PublishRelay<Void>()
    private let deleteSentenceRelay   = PublishRelay<Sentence>()

    private lazy var viewModel = AllSentenceViewModel(
        sentenceRepository: AppContainer.shared.sentenceRepository,
        bookRepository:     AppContainer.shared.bookRepository
    )

    private var items: [AllSentenceDisplayItem] = []
    private var expandedIDs: Set<UUID> = []

    // MARK: - UI

    private lazy var backButton: UIButton = {
        let btn = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        btn.setImage(UIImage(systemName: "chevron.left", withConfiguration: cfg), for: .normal)
        btn.tintColor = UIColor.accent
        return btn
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.text = "밑줄 모아보기"
        l.font = UIFont(name: "GowunBatang-Bold", size: 34) ?? .systemFont(ofSize: 34, weight: .bold)
        l.textColor = .accent
        l.adjustsFontSizeToFitWidth = true
        l.minimumScaleFactor = 0.7
        return l
    }()

    private let searchBarView: UIView = {
        let v = UIView()
        v.backgroundColor    = UIColor.background
        v.layer.cornerRadius = 10
        v.layer.borderWidth  = 1
        v.layer.borderColor  = UIColor.walnut.cgColor
        return v
    }()

    private let searchIconView: UIImageView = {
        let iv = UIImageView()
        let cfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        iv.image       = UIImage(systemName: "magnifyingglass", withConfiguration: cfg)
        iv.tintColor   = UIColor.walnut
        iv.contentMode = .scaleAspectFit
        return iv
    }()

    private let searchTextField: UITextField = {
        let tf = UITextField()
        let placeholderFont = UIFont(name: "GoyangIlsan R", size: 14) ?? .systemFont(ofSize: 14)
        tf.attributedPlaceholder = NSAttributedString(
            string: "책 제목 또는 저자 검색",
            attributes: [
                .font:            placeholderFont,
                .foregroundColor: UIColor.accent.withAlphaComponent(0.5),
            ]
        )
        tf.font            = placeholderFont
        tf.textColor       = UIColor.accent
        tf.backgroundColor = .clear
        tf.returnKeyType   = .search
        return tf
    }()

    private let tableView: UITableView = {
        let tv = UITableView()
        tv.backgroundColor            = .background
        tv.rowHeight                  = UITableView.automaticDimension
        tv.estimatedRowHeight         = 88
        tv.separatorColor             = UIColor.appPrimary.withAlphaComponent(0.15)
        tv.separatorInset             = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 0)
        tv.keyboardDismissMode        = .onDrag
        tv.showsVerticalScrollIndicator = false
        return tv
    }()

    private let emptyLabel: UILabel = {
        let l = UILabel()
        l.text          = "저장된 밑줄이 없어요"
        l.font          = UIFont(name: "GowunBatang-Regular", size: 16) ?? .systemFont(ofSize: 16)
        l.textColor     = UIColor.appPrimary.withAlphaComponent(0.5)
        l.textAlignment = .center
        l.isHidden      = true
        return l
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .background
        setupUI()
        setupConstraints()
        bindViewModel()
        bindActions()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.interactivePopGestureRecognizer?.delegate = nil
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        viewWillAppearRelay.accept(())
    }

    // MARK: - Setup

    private func setupUI() {
        let headerView = UIView()
        headerView.addSubview(backButton)
        headerView.addSubview(titleLabel)

        searchBarView.addSubview(searchIconView)
        searchBarView.addSubview(searchTextField)

        view.addSubview(headerView)
        view.addSubview(searchBarView)
        view.addSubview(tableView)
        view.addSubview(emptyLabel)

        tableView.register(AllSentenceCell.self, forCellReuseIdentifier: AllSentenceCell.reuseIdentifier)
        tableView.dataSource = self
        tableView.delegate   = self

        headerView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.leading.trailing.equalToSuperview().inset(24)
            make.height.equalTo(54)
        }
        backButton.snp.makeConstraints { make in
            make.leading.centerY.equalToSuperview()
            make.size.equalTo(CGSize(width: 32, height: 44))
        }
        titleLabel.snp.makeConstraints { make in
            make.leading.equalTo(backButton.snp.trailing).offset(4)
            make.centerY.equalToSuperview()
            make.trailing.lessThanOrEqualToSuperview()
        }
    }

    private func setupConstraints() {
        searchBarView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(60)
            make.leading.trailing.equalToSuperview().inset(24)
            make.height.equalTo(48)
        }
        searchIconView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.centerY.equalToSuperview()
            make.size.equalTo(18)
        }
        searchTextField.snp.makeConstraints { make in
            make.leading.equalTo(searchIconView.snp.trailing).offset(10)
            make.trailing.equalToSuperview().inset(16)
            make.centerY.equalToSuperview()
        }
        tableView.snp.makeConstraints { make in
            make.top.equalTo(searchBarView.snp.bottom)
            make.leading.trailing.bottom.equalToSuperview()
        }
        emptyLabel.snp.makeConstraints { make in
            make.center.equalTo(view.safeAreaLayoutGuide)
        }
    }

    // MARK: - Bindings

    private func bindViewModel() {
        let output = viewModel.transform(input: AllSentenceViewModel.Input(
            viewWillAppear:  viewWillAppearRelay.asObservable(),
            searchQuery:     searchTextField.rx.text.orEmpty.distinctUntilChanged().asObservable(),
            deleteSentence:  deleteSentenceRelay.asObservable()
        ))

        output.items
            .drive(onNext: { [weak self] items in
                guard let self else { return }
                self.items = items
                self.expandedIDs = self.expandedIDs.filter { id in items.contains { $0.sentence.id == id } }
                self.tableView.reloadData()
                self.emptyLabel.isHidden = !items.isEmpty
            })
            .disposed(by: disposeBag)

        output.errorMessage
            .emit(onNext: { [weak self] _ in
                self?.emptyLabel.isHidden = false
            })
            .disposed(by: disposeBag)
    }

    private func bindActions() {
        backButton.rx.tap
            .subscribe(onNext: { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            })
            .disposed(by: disposeBag)
    }
}

// MARK: - UITableViewDataSource & Delegate

extension AllSentenceViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: AllSentenceCell.reuseIdentifier,
            for: indexPath
        ) as! AllSentenceCell
        let item = items[indexPath.row]
        cell.configure(with: item, isExpanded: expandedIDs.contains(item.sentence.id))
        return cell
    }

    func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let delete = UIContextualAction(style: .destructive, title: "삭제") { [weak self] _, _, completion in
            guard let self else { completion(false); return }
            let item = self.items[indexPath.row]
            self.expandedIDs.remove(item.sentence.id)
            self.items.remove(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .automatic)
            self.emptyLabel.isHidden = !self.items.isEmpty
            self.deleteSentenceRelay.accept(item.sentence)
            WidgetCacheService.shared.refreshCache()
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        let id = items[indexPath.row].sentence.id
        if expandedIDs.contains(id) {
            expandedIDs.remove(id)
        } else {
            expandedIDs.insert(id)
        }
        tableView.performBatchUpdates({
            tableView.reloadRows(at: [indexPath], with: .automatic)
        })
    }
}
