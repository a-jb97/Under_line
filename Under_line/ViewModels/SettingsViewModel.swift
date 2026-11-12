//
//  SettingsViewModel.swift
//  Under_line
//
//  설정 화면 ViewModel — 백업 / 복원 비즈니스 로직
//

import Foundation
import RxSwift
import RxCocoa
import SwiftData

@MainActor
final class SettingsViewModel {

    struct Input {
        var preferenceSelected: Observable<BookPurchasePreference> = .empty()
        let backupTap: Observable<Void>
        let restoreFilePicked: Observable<URL>
    }

    struct Output {
        let purchasePreference: Driver<BookPurchasePreference>
        let exportFileURL: Observable<URL>
        let toastMessage: Observable<String>
        let restoreSucceeded: Observable<Void>
    }

    private let preferences: BookPurchasePreferenceStoreProtocol
    private let preference: BehaviorRelay<BookPurchasePreference>
    private let backupService: BackupService
    private let disposeBag = DisposeBag()

    init(preferences: BookPurchasePreferenceStoreProtocol = AppContainer.shared.bookPurchasePreferenceStore) {
        self.preferences = preferences
        self.preference = BehaviorRelay(value: preferences.current)
        self.backupService = BackupService(modelContext: AppContainer.shared.modelContainer.mainContext)
    }

    func transform(input: Input) -> Output {
        input.preferenceSelected.subscribe(onNext: { [weak self] value in
            self?.preferences.save(value)
            self?.preference.accept(value)
        }).disposed(by: disposeBag)
        let exportResult = input.backupTap
            .flatMapLatest { [weak self] _ -> Observable<Result<URL, Error>> in
                guard let self else { return .empty() }
                return rxAsync { try await self.backupService.exportToJSON() }
                    .map { Result<URL, Error>.success($0) }
                    .catch { Observable.just(.failure($0)) }
            }
            .share()

        let exportFileURL = exportResult
            .compactMap { result -> URL? in
                if case .success(let url) = result { return url }
                return nil
            }

        let exportError = exportResult
            .compactMap { result -> String? in
                if case .failure(let error) = result {
                    return "백업 실패: \(error.localizedDescription)"
                }
                return nil
            }

        let restoreResult = input.restoreFilePicked
            .flatMapLatest { [weak self] url -> Observable<Result<Void, Error>> in
                guard let self else { return .empty() }
                return rxAsync { try await self.backupService.restore(from: url) }
                    .map { Result<Void, Error>.success(()) }
                    .catch { Observable.just(.failure($0)) }
            }
            .share()

        restoreResult
            .filter { if case .success = $0 { return true }; return false }
            .subscribe(onNext: { _ in AppContainer.shared.reloadBookRelay() })
            .disposed(by: disposeBag)

        let restoreSuccess = restoreResult
            .compactMap { result -> String? in
                if case .success = result { return "밑줄 기록이 복원되었습니다." }
                return nil
            }

        let restoreError = restoreResult
            .compactMap { result -> String? in
                if case .failure(let error) = result {
                    return "복원 실패: \(error.localizedDescription)"
                }
                return nil
            }

        let toastMessage = Observable.merge(exportError, restoreSuccess, restoreError)

        let restoreSucceeded = restoreResult
            .compactMap { result -> Void? in
                if case .success = result { return () }
                return nil
            }

        return Output(
            purchasePreference: preference.asDriver(),
            exportFileURL:    exportFileURL,
            toastMessage:     toastMessage,
            restoreSucceeded: restoreSucceeded
        )
    }
}
