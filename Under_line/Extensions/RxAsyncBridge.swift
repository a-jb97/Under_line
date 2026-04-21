//
//  RxAsyncBridge.swift
//  Under_line
//
//  async throws 함수를 RxSwift Observable로 감싸는 헬퍼
//

import RxSwift

/// async throws 작업을 Observable<T>로 래핑한다.
/// Task가 취소되면 Disposable 해제 시점에 cancel된다.
func rxAsync<T>(_ work: @escaping () async throws -> T) -> Observable<T> {
    Observable.create { observer in
        let task = Task { @MainActor in
            do {
                let result = try await work()
                observer.onNext(result)
                observer.onCompleted()
            } catch {
                observer.onError(error)
            }
        }
        return Disposables.create { task.cancel() }
    }
}
