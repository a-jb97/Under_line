//
//  RandomUnderLineViewModel.swift
//  Under_line
//
//  앱 실행 시 감정 선택 → 랜덤 문장 표시 기능의 ViewModel
//

import RxSwift
import RxCocoa

final class RandomUnderLineViewModel {

    struct Input {
        let viewDidLoad:     Observable<Void>
        let emotionSelected: Observable<Emotion>
    }

    struct Output {
        /// 문장이 존재하는 감정 목록. 빈 배열이면 저장된 문장 없음 → 모달 표시 생략
        let shouldPresentEmotionPicker: Signal<[Emotion]>
        /// 선택된 감정에 해당하는 랜덤 문장
        let randomSentence: Signal<Sentence>
    }

    private let repository: SentenceRepositoryProtocol
    private let disposeBag = DisposeBag()

    init(repository: SentenceRepositoryProtocol) {
        self.repository = repository
    }

    func transform(input: Input) -> Output {
        let allSentences           = BehaviorRelay<[Sentence]>(value: [])
        let emotionPickerRelay     = PublishRelay<[Emotion]>()
        let randomSentenceRelay    = PublishRelay<Sentence>()

        // 1. 앱 시작 시 전체 문장 로드
        input.viewDidLoad
            .flatMapLatest { [weak self] _ -> Observable<[Sentence]> in
                guard let self else { return .just([]) }
                return rxAsync { try await self.repository.fetchAllSentences() }
                    .catch { _ in .just([]) }
            }
            .do(onNext: { allSentences.accept($0) })
            .map { sentences -> [Emotion] in
                guard !sentences.isEmpty else { return [] }
                return Emotion.allCases.filter { e in sentences.contains { $0.emotion == e } }
            }
            .bind(to: emotionPickerRelay)
            .disposed(by: disposeBag)

        // 2. 감정 선택 → 해당 감정의 랜덤 문장 방출
        input.emotionSelected
            .withLatestFrom(allSentences) { (emotion: $0, sentences: $1) }
            .compactMap { pair -> Sentence? in
                pair.sentences.filter { $0.emotion == pair.emotion }.randomElement()
            }
            .bind(to: randomSentenceRelay)
            .disposed(by: disposeBag)

        return Output(
            shouldPresentEmotionPicker: emotionPickerRelay.asSignal(),
            randomSentence:             randomSentenceRelay.asSignal()
        )
    }
}
