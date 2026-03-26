//
//  DirectCollectViewModel.swift
//  Under_line
//
//  수동 문장 수집 시트 ViewModel — 폼 유효성 검사 + 저장 처리
//

import Foundation
import RxSwift
import RxCocoa

final class DirectCollectViewModel {

    // MARK: - Input

    struct Input {
        let sentence: Observable<String>    // 밑줄 내용
        let page:     Observable<String>    // 페이지 번호 (문자열)
        let emotion:  Observable<Emotion?>  // 선택된 감정
        let memo:     Observable<String>    // 메모
        let saveTap:  Observable<Void>      // 추가하기 버튼 탭
    }

    // MARK: - Output

    struct Output {
        let isFormValid:   Driver<Bool>    // 추가하기 버튼 활성화 여부
        let saveCompleted: Signal<Void>    // 저장 완료 → 시트 닫기
        let errorMessage:  Signal<String>  // Toast 메시지 (1회성)
    }

    // MARK: - Dependencies

    private let bookISBN: String
    private let repository: SentenceRepositoryProtocol
    private let disposeBag = DisposeBag()

    init(bookISBN: String, repository: SentenceRepositoryProtocol) {
        self.bookISBN   = bookISBN
        self.repository = repository
    }

    // MARK: - Transform

    func transform(input: Input) -> Output {
        let errorMessage  = PublishRelay<String>()
        let saveCompleted = PublishRelay<Void>()

        let isFormValid = Observable.combineLatest(
            input.sentence,
            input.page,
            input.emotion
        ) { sentence, page, emotion -> Bool in
            let sentenceValid = !sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let pageNum = Int(page.trimmingCharacters(in: .whitespacesAndNewlines))
            return sentenceValid && pageNum != nil && pageNum! > 0 && emotion != nil
        }
        .asDriver(onErrorJustReturn: false)

        let formData = Observable.combineLatest(
            input.sentence,
            input.page,
            input.emotion,
            input.memo
        )

        input.saveTap
            .withLatestFrom(formData)
            .flatMapLatest { [weak self] (sentence, page, emotion, memo) -> Observable<Void> in
                guard let self,
                      let pageNum = Int(page.trimmingCharacters(in: .whitespacesAndNewlines)),
                      let localEmotion = emotion else { return .empty() }

                let memoText = memo.trimmingCharacters(in: .whitespacesAndNewlines)
                let newSentence = Sentence(
                    id:       UUID(),
                    bookISBN: self.bookISBN,
                    sentence: sentence.trimmingCharacters(in: .whitespacesAndNewlines),
                    page:     pageNum,
                    emotion:  localEmotion,
                    memo:     memoText.isEmpty ? nil : memoText,
                    date:     Date()
                )

                return self.repository.saveSentence(newSentence)
                    .andThen(.just(()))
                    .catch { error in
                        errorMessage.accept(error.localizedDescription)
                        return .empty()
                    }
                    .asObservable()
            }
            .bind(to: saveCompleted)
            .disposed(by: disposeBag)

        return Output(
            isFormValid:   isFormValid,
            saveCompleted: saveCompleted.asSignal(),
            errorMessage:  errorMessage.asSignal()
        )
    }
}
