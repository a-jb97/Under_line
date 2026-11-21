import UIKit
import Vision
import RxSwift
import RxCocoa

final class OCRMarkupViewModel {
    struct Input {
        let recognize: Observable<Void>
        let strokes: Observable<[[CGPoint]]>
    }

    struct Output {
        let text: Driver<String>
        let hasStrokes: Driver<Bool>
        let isRecognizing: Driver<Bool>
        let hasRecognizedText: Driver<Bool>
        let error: Signal<String>
    }

    private let image: UIImage
    private let disposeBag = DisposeBag()
    private let observations = BehaviorRelay<[VNRecognizedTextObservation]>(value: [])
    private let busy = BehaviorRelay(value: false)
    private let error = PublishRelay<String>()

    init(image: UIImage) { self.image = image }

    func transform(input: Input) -> Output {
        input.recognize.take(1)
            .do(onNext: { [weak self] in self?.busy.accept(true) })
            .flatMapLatest { [weak self] _ -> Observable<[VNRecognizedTextObservation]> in
                guard let self else { return .empty() }
                return rxAsync {
                    guard let cgImage = self.image.cgImage else { throw RecognitionError.invalidImage }
                    return try await Task.detached(priority: .userInitiated) {
                        let request = VNRecognizeTextRequest()
                        request.recognitionLevel = .accurate
                        request.recognitionLanguages = ["ko-KR", "en-US"]
                        request.usesLanguageCorrection = true
                        try VNImageRequestHandler(cgImage: cgImage, orientation: .up).perform([request])
                        try Task.checkCancellation()
                        return request.results ?? []
                    }.value
                }.catch { [weak self] failure in
                    if !(failure is CancellationError) { self?.error.accept("텍스트를 인식하지 못했습니다. 다른 사진으로 다시 시도해주세요.") }
                    return .just([])
                }.do(onDispose: { [weak self] in self?.busy.accept(false) })
            }
            .bind(to: observations).disposed(by: disposeBag)

        let strokes = input.strokes.startWith([]).share(replay: 1, scope: .whileConnected)
        let text = Observable.combineLatest(observations, strokes)
            .map { observations, strokes in Self.selectedText(observations: observations, strokes: strokes) }
            .asDriver(onErrorJustReturn: "")
        return Output(text: text,
                      hasStrokes: strokes.map { !$0.isEmpty }.asDriver(onErrorJustReturn: false),
                      isRecognizing: busy.asDriver(),
                      hasRecognizedText: observations.map { !$0.isEmpty }.asDriver(onErrorJustReturn: false),
                      error: error.asSignal())
    }

    private enum RecognitionError: Error { case invalidImage }

    /// 좌상단 원점의 이미지 정규화 좌표만 사용한다. 화면 크기는 선택 결과에 영향을 주지 않는다.
    private static func selectedText(observations: [VNRecognizedTextObservation], strokes: [[CGPoint]]) -> String {
        var selection: [Int: ClosedRange<CGFloat>] = [:]
        for points in strokes where points.count > 1 {
            let xs = points.map(\.x)
            let ys = points.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { continue }
            let range = max(0, minX - 0.01)...min(1, maxX + 0.01)
            let y = (minY + maxY) / 2
            let candidates = observations.enumerated().compactMap { index, observation -> (Int, CGRect)? in
                let box = observation.boundingBox
                let rect = CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
                guard rect.maxX >= range.lowerBound, rect.minX <= range.upperBound,
                      y >= rect.minY, y <= rect.maxY + max(0.015, rect.height) else { return nil }
                return (index, rect)
            }
            guard let closest = candidates.min(by: { abs($0.1.maxY - y) < abs($1.1.maxY - y) }) else { continue }
            for (index, rect) in candidates where abs(rect.maxY - closest.1.maxY) <= max(0.008, closest.1.height * 0.3) {
                if let previous = selection[index] {
                    selection[index] = min(previous.lowerBound, range.lowerBound)...max(previous.upperBound, range.upperBound)
                } else { selection[index] = range }
            }
        }
        return selection.keys.sorted { lhs, rhs in
            let a = observations[lhs].boundingBox
            let b = observations[rhs].boundingBox
            return abs(a.midY - b.midY) > 0.02 ? a.midY > b.midY : a.minX < b.minX
        }.compactMap { index -> String? in
            guard let candidate = observations[index].topCandidates(1).first, let range = selection[index] else { return nil }
            let text = candidate.string
            var result: [Substring] = []
            var cursor = text.startIndex
            while cursor < text.endIndex {
                while cursor < text.endIndex, text[cursor].isWhitespace { cursor = text.index(after: cursor) }
                guard cursor < text.endIndex else { break }
                let start = cursor
                while cursor < text.endIndex, !text[cursor].isWhitespace { cursor = text.index(after: cursor) }
                let word = start..<cursor
                if let box = try? candidate.boundingBox(for: word),
                   !(box.boundingBox.minX...box.boundingBox.maxX).overlaps(range) { continue }
                result.append(text[word])
            }
            return result.isEmpty ? nil : result.joined(separator: " ")
        }.joined(separator: " ")
    }
}
