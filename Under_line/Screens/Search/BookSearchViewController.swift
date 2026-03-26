//
//  BookSearchViewController.swift
//  Under_line
//
//  FAB 탭 시 present되는 도서 등록 검색 시트 (Node 588fl)
//

import UIKit
import SnapKit
import RxSwift
import RxCocoa
import Kingfisher
import Toast

final class BookSearchViewController: UIViewController {

    // MARK: - Properties

    private let disposeBag = DisposeBag()
    private let viewModel  = BookSearchViewModel(repository: AppContainer.shared.bookRepository)
    private let loadNextPageRelay  = PublishRelay<Void>()
    private let registerBookRelay  = PublishRelay<Book>()

    // MARK: - UI Components

    private let handleBar: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.walnut.withAlphaComponent(0.25)
        v.layer.cornerRadius = 2.5
        return v
    }()

    private let sheetTitleLabel: UILabel = {
        let l = UILabel()
        l.text = "도서 검색"
        l.font = UIFont(name: "GowunBatang-Bold", size: 22)
            ?? .systemFont(ofSize: 22, weight: .semibold)
        l.textColor = UIColor(hex: "#190e0b")
        return l
    }()

    private let searchBarView: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.background
        v.layer.cornerRadius = 10
        v.layer.borderWidth  = 1
        v.layer.borderColor  = UIColor.walnut.cgColor
        return v
    }()

    private let searchIconView: UIImageView = {
        let iv = UIImageView()
        let cfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        iv.image = UIImage(systemName: "magnifyingglass", withConfiguration: cfg)
        iv.tintColor    = UIColor.walnut
        iv.contentMode  = .scaleAspectFit
        return iv
    }()

    private let searchTextField: UITextField = {
        let tf = UITextField()
        let placeholderFont = UIFont(name: "GoyangIlsan R", size: 14)
            ?? .systemFont(ofSize: 14)
        tf.attributedPlaceholder = NSAttributedString(
            string: "책 제목 또는 저자를 검색하세요",
            attributes: [
                .font:            placeholderFont,
                .foregroundColor: UIColor(hex: "#190e0b").withAlphaComponent(0.5),
            ]
        )
        tf.font            = placeholderFont
        tf.textColor       = UIColor(hex: "#190e0b")
        tf.backgroundColor = .clear
        tf.returnKeyType   = .search
        return tf
    }()

    private let directRegisterButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("직접 등록", for: .normal)
        btn.titleLabel?.font = UIFont(name: "GoyangIlsan R", size: 14)
            ?? .systemFont(ofSize: 14)
        btn.setTitleColor(UIColor.walnut, for: .normal)
        btn.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        return btn
    }()

    private let tableView: UITableView = {
        let tv = UITableView()
        tv.backgroundColor               = .clear
        tv.separatorStyle                = .none
        tv.showsVerticalScrollIndicator  = false
        tv.clipsToBounds                 = false
        tv.rowHeight                     = UITableView.automaticDimension
        tv.estimatedRowHeight            = 104
        tv.register(BookRowCell.self, forCellReuseIdentifier: BookRowCell.reuseID)
        return tv
    }()

    private let activityIndicator: UIActivityIndicatorView = {
        let ai = UIActivityIndicatorView(style: .medium)
        ai.color = UIColor.walnut
        ai.hidesWhenStopped = true
        return ai
    }()

    private let headerBackground: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.background
        return v
    }()

    private let bestsellerLabel: UILabel = {
        let l = UILabel()
        l.text            = "베스트셀러 50"
        l.font            = UIFont(name: "GowunBatang-Bold", size: 14) ?? .systemFont(ofSize: 14)
        l.textColor       = UIColor.primary
        l.backgroundColor = UIColor.background
        return l
    }()

    private let loadMoreIndicator: UIActivityIndicatorView = {
        let ai = UIActivityIndicatorView(style: .medium)
        ai.color = UIColor.walnut
        ai.frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 48)
        ai.startAnimating()
        return ai
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupConstraints()
        bindViewModel()
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = UIColor.background

        view.addSubview(tableView)
        view.addSubview(activityIndicator)
        view.addSubview(headerBackground)   // tableView 위, 헤더 뷰 아래 → 오버플로 셀 차단

        view.addSubview(handleBar)
        view.addSubview(sheetTitleLabel)
        view.addSubview(directRegisterButton)

        searchBarView.addSubview(searchIconView)
        searchBarView.addSubview(searchTextField)
        view.addSubview(searchBarView)
        setupTableHeader()
    }

    private func setupTableHeader() {
        let container = UIView()
        container.backgroundColor = .clear
        container.addSubview(bestsellerLabel)
        bestsellerLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview()
            make.top.equalToSuperview().offset(10)
            make.bottom.equalToSuperview().inset(6)
        }
        container.frame = CGRect(x: 0, y: 0, width: 0, height: 36)
        tableView.tableHeaderView = container
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
            make.leading.equalToSuperview().inset(24)
            make.trailing.lessThanOrEqualTo(directRegisterButton.snp.leading).offset(-12)
            make.height.equalTo(52)
        }

        directRegisterButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(24)
            make.centerY.equalTo(sheetTitleLabel)
        }

        searchBarView.snp.makeConstraints { make in
            make.top.equalTo(sheetTitleLabel.snp.bottom)
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
            make.leading.trailing.equalToSuperview().inset(24)
            make.bottom.equalTo(view.safeAreaLayoutGuide)
        }

        activityIndicator.snp.makeConstraints { make in
            make.center.equalTo(tableView)
        }

        headerBackground.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.bottom.equalTo(searchBarView.snp.bottom)
        }
    }

    // MARK: - Bindings

    private func bindViewModel() {
        let input = BookSearchViewModel.Input(
            viewDidLoad:   .just(()),
            searchQuery:   searchTextField.rx.text.orEmpty.asObservable(),
            searchTrigger: searchTextField.rx.controlEvent(.editingDidEndOnExit).asObservable(),
            loadNextPage:  loadNextPageRelay.asObservable(),
            registerBook:  registerBookRelay.asObservable()
        )

        let output = viewModel.transform(input: input)

        output.books
            .drive(tableView.rx.items(cellIdentifier: BookRowCell.reuseID, cellType: BookRowCell.self)) { [weak self] _, book, cell in
                cell.configure(book: book)
                cell.onRegister = { [weak self] registeredBook in
                    self?.registerBookRelay.accept(registeredBook)
                }
            }
            .disposed(by: disposeBag)

        output.isLoading
            .drive(activityIndicator.rx.isAnimating)
            .disposed(by: disposeBag)

        output.isLoadingMore
            .drive(onNext: { [weak self] loading in
                guard let self else { return }
                self.tableView.tableFooterView = loading ? self.loadMoreIndicator : UIView()
            })
            .disposed(by: disposeBag)

        output.errorMessage
            .emit(onNext: { [weak self] message in
                var style = ToastStyle()
                style.backgroundColor = UIColor.primary.withAlphaComponent(0.9)
                style.messageFont = UIFont(name: "GowunBatang-Regular", size: 14) ?? .systemFont(ofSize: 14)
                self?.view.makeToast(message, duration: 1.2, position: .center, style: style)
            })
            .disposed(by: disposeBag)

        output.registerCompleted
            .emit(onNext: { [weak self] in
                self?.dismiss(animated: true)
            })
            .disposed(by: disposeBag)

        // 마지막 셀이 표시될 때 다음 페이지 요청
        tableView.rx.willDisplayCell
            .filter { [weak self] _, indexPath in
                guard let self else { return false }
                return indexPath.row == self.tableView.numberOfRows(inSection: 0) - 1
            }
            .map { _ in }
            .bind(to: loadNextPageRelay)
            .disposed(by: disposeBag)

        // 검색 버튼 탭 시 헤더 영구 숨김 (dismiss 전까지 복원 안 함)
        searchTextField.rx.controlEvent(.editingDidEndOnExit)
            .take(1)
            .subscribe(onNext: { [weak self] in
                guard let self, let header = self.tableView.tableHeaderView else { return }
                self.bestsellerLabel.isHidden = true
                header.frame.size.height = 0
                self.tableView.tableHeaderView = header
            })
            .disposed(by: disposeBag)

        // 스크롤 시 키보드 내리기
        tableView.rx.didScroll
            .subscribe(onNext: { [weak self] in
                self?.view.endEditing(false)
            })
            .disposed(by: disposeBag)

        // 직접 등록 버튼
        directRegisterButton.rx.tap
            .subscribe(onNext: { [weak self] in
                let vc = DirectRegisterViewController()
                if let sheet = vc.sheetPresentationController {
                    sheet.detents              = [.large()]
                    sheet.prefersGrabberVisible = false
                    sheet.preferredCornerRadius = 24
                }
                self?.present(vc, animated: true)
            })
            .disposed(by: disposeBag)
    }
}

// MARK: - BookRowCell

private final class BookRowCell: UITableViewCell {

    static let reuseID = "BookRowCell"

    // MARK: - UI

    private let cardView: UIView = {
        let v = UIView()
        v.backgroundColor     = UIColor.background
        v.layer.cornerRadius  = 16
        v.layer.masksToBounds = false
        v.layer.shadowColor   = UIColor(hex: "#5d4037").cgColor
        v.layer.shadowOpacity = Float(CGFloat(0x30) / 255)
        v.layer.shadowRadius  = 4
        v.layer.shadowOffset  = CGSize(width: 4, height: 4)
        return v
    }()

    private let rankLabel: UILabel = {
        let l = UILabel()
        l.font          = UIFont(name: "GoyangIlsan L", size: 18) ?? .boldSystemFont(ofSize: 18)
        l.textColor     = UIColor(hex: "#190e0b")
        l.textAlignment = .center
        l.setContentHuggingPriority(.required, for: .horizontal)
        return l
    }()

    private let thumbnailImageView: UIImageView = {
        let iv = UIImageView()
        iv.backgroundColor    = UIColor.walnut
        iv.layer.cornerRadius = 3
        iv.clipsToBounds      = true
        iv.contentMode        = .scaleAspectFill
        return iv
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font          = UIFont(name: "GowunBatang-Regular", size: 16)
            ?? .systemFont(ofSize: 16, weight: .medium)
        l.textColor     = UIColor(hex: "#190e0b")
        l.numberOfLines = 2
        return l
    }()

    private let authorLabel: UILabel = {
        let l = UILabel()
        l.font      = UIFont(name: "GowunBatang-Regular", size: 13)
            ?? .systemFont(ofSize: 13)
        l.textColor = UIColor.walnut
        return l
    }()

    private let registerButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setTitle("등록", for: .normal)
        btn.titleLabel?.font = UIFont(name: "GoyangIlsan R", size: 13)
            ?? .systemFont(ofSize: 13, weight: .medium)
        btn.setTitleColor(UIColor.walnut, for: .normal)
        btn.layer.cornerRadius = 7
        btn.layer.borderWidth  = 1
        btn.layer.borderColor  = UIColor.walnut.cgColor
        btn.contentEdgeInsets  = UIEdgeInsets(top: 7, left: 14, bottom: 7, right: 14)
        btn.setContentHuggingPriority(.required, for: .horizontal)
        btn.setContentCompressionResistancePriority(.required, for: .horizontal)
        return btn
    }()

    var onRegister: ((Book) -> Void)?
    private var currentBook: Book?

    /// nil = 아직 미설정 (첫 configure 시 반드시 레이아웃 업데이트)
    private var rankVisible: Bool?

    // MARK: - Init

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupCell()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Setup

    private func setupCell() {
        selectionStyle              = .none
        backgroundColor             = .clear
        contentView.backgroundColor = .clear
        contentView.clipsToBounds   = false

        contentView.addSubview(cardView)

        let textStack = UIStackView(arrangedSubviews: [titleLabel, authorLabel])
        textStack.axis    = .vertical
        textStack.spacing = 3

        [rankLabel, thumbnailImageView, textStack, registerButton].forEach {
            cardView.addSubview($0)
        }

        cardView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(6)
            make.bottom.equalToSuperview().inset(6)
            make.leading.trailing.equalToSuperview()
            make.height.greaterThanOrEqualTo(80)
        }

        rankLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.centerY.equalToSuperview()
            make.width.equalTo(20)
        }

        // thumbnailImageView 초기 constraints — rank 표시 모드 (configure에서 remakeConstraints)
        thumbnailImageView.snp.makeConstraints { make in
            make.leading.equalTo(rankLabel.snp.trailing).offset(14)
            make.centerY.equalToSuperview()
            make.width.equalTo(48)
            make.height.equalTo(64)
        }

        textStack.snp.makeConstraints { make in
            make.leading.equalTo(thumbnailImageView.snp.trailing).offset(14)
            make.trailing.lessThanOrEqualTo(registerButton.snp.leading).offset(-14)
            make.centerY.equalToSuperview()
        }

        registerButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(16)
            make.centerY.equalToSuperview()
        }

        registerButton.addTarget(self, action: #selector(registerTapped), for: .touchUpInside)
    }

    @objc private func registerTapped() {
        guard let book = currentBook else { return }
        onRegister?(book)
    }

    // MARK: - Configure

    func configure(book: Book) {
        currentBook      = book
        rankLabel.text   = book.bestRank.map { "\($0)" }
        titleLabel.text  = book.title
        authorLabel.text = book.author
        thumbnailImageView.kf.setImage(with: book.coverURL)

        let showRank = book.bestRank != nil
        guard showRank != rankVisible else { return }
        rankVisible        = showRank
        rankLabel.isHidden = !showRank
        updateThumbnailLeading(showRank: showRank)
    }

    private func updateThumbnailLeading(showRank: Bool) {
        thumbnailImageView.snp.remakeConstraints { make in
            if showRank {
                make.leading.equalTo(rankLabel.snp.trailing).offset(14)
            } else {
                make.leading.equalToSuperview().offset(16)
            }
            make.centerY.equalToSuperview()
            make.width.equalTo(48)
            make.height.equalTo(64)
        }
    }
}
