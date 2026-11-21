import UIKit

enum OCRImageGeometry {
    /// Vision과 화면이 동일한 방향의 픽셀 이미지를 사용하게 한다.
    static func uprightImage(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up, let cgImage = image.cgImage else { return image }
        let swapsAxes: Bool
        switch image.imageOrientation {
        case .left, .right, .leftMirrored, .rightMirrored: swapsAxes = true
        default: swapsAxes = false
        }
        let size = CGSize(width: swapsAxes ? cgImage.height : cgImage.width,
                          height: swapsAxes ? cgImage.width : cgImage.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    static func displayRect(imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else { return .zero }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
    }

    static func normalizedPoint(_ point: CGPoint, in imageRect: CGRect) -> CGPoint? {
        guard imageRect.width > 0, imageRect.height > 0 else { return nil }
        return CGPoint(x: min(1, max(0, (point.x - imageRect.minX) / imageRect.width)),
                       y: min(1, max(0, (point.y - imageRect.minY) / imageRect.height)))
    }

    static func viewPoint(_ point: CGPoint, in imageRect: CGRect) -> CGPoint {
        CGPoint(x: imageRect.minX + point.x * imageRect.width, y: imageRect.minY + point.y * imageRect.height)
    }
}
