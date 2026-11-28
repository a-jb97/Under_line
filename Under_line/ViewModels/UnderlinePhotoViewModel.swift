import Foundation
import Photos
import RxSwift
import RxCocoa

final class UnderlinePhotoViewModel {
    struct Input {
        let saveTap: Observable<Void>
    }

    struct Output {
        let saveMessage: Signal<String>
    }

    private let photoData: Data

    init(photoData: Data) {
        self.photoData = photoData
    }

    func transform(input: Input) -> Output {
        let saveMessage = input.saveTap
            .flatMapFirst { [photoData] in
                rxAsync {
                    let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                    guard status == .authorized || status == .limited else {
                        return "설정에서 사진 추가 권한을 허용해주세요."
                    }
                    do {
                        try await PHPhotoLibrary.shared().performChanges {
                            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: photoData, options: nil)
                        }
                        return "밑줄 사진을 저장했어요."
                    } catch {
                        return "사진을 저장하지 못했어요. 다시 시도해주세요."
                    }
                }
            }
            .asSignal(onErrorJustReturn: "사진을 저장하지 못했어요. 다시 시도해주세요.")
        return Output(saveMessage: saveMessage)
    }
}
