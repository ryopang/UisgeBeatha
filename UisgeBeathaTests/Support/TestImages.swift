import UIKit

/// Small synthetic JPEGs for photo tests.
enum TestImages {
    static func jpeg(width: CGFloat = 600, height: CGFloat = 400, color: UIColor = .systemOrange) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        let image = renderer.image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return image.jpegData(compressionQuality: 0.9) ?? Data()
    }
}
