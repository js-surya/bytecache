import CoreGraphics
import CoreImage
import Vision

/// Photos of paper or a screen taken at an angle: Vision finds the page's four corners and the photo
/// is flattened to just the page before text recognition, as document scanners (Notes, Files) do.
/// Screenshots and photos without a clear page are left alone.
enum PageStraightening {
    /// Corners in pixels, origin bottom-left (Core Image's), as Vision reports them.
    struct Quad: Equatable {
        var topLeft, topRight, bottomLeft, bottomRight: CGPoint
    }

    /// The page in `image`, flattened, or nil when there's no clear page or it's already the whole image.
    static func straightened(_ image: CGImage) -> CGImage? {
        let request = VNDetectDocumentSegmentationRequest()
        guard (try? VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])) != nil,
              let page = request.results?.first else { return nil }
        let w = CGFloat(image.width), h = CGFloat(image.height)
        func pixels(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * w, y: p.y * h) }
        let quad = Quad(topLeft: pixels(page.topLeft), topRight: pixels(page.topRight),
                        bottomLeft: pixels(page.bottomLeft), bottomRight: pixels(page.bottomRight))
        guard worthStraightening(quad, confidence: page.confidence, imageSize: CGSize(width: w, height: h)) else { return nil }
        let filter = CIFilter(name: "CIPerspectiveCorrection")!
        filter.setValue(CIImage(cgImage: image), forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgPoint: quad.topLeft), forKey: "inputTopLeft")
        filter.setValue(CIVector(cgPoint: quad.topRight), forKey: "inputTopRight")
        filter.setValue(CIVector(cgPoint: quad.bottomLeft), forKey: "inputBottomLeft")
        filter.setValue(CIVector(cgPoint: quad.bottomRight), forKey: "inputBottomRight")
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }

    /// A confident page that covers a good part of the photo but not all of it (then there's nothing to fix).
    static func worthStraightening(_ quad: Quad, confidence: Float, imageSize: CGSize) -> Bool {
        guard confidence >= 0.8 else { return false }
        let corners = [quad.topLeft, quad.topRight, quad.bottomRight, quad.bottomLeft]
        // Shoelace formula.
        var twice: CGFloat = 0
        for i in corners.indices {
            let a = corners[i], b = corners[(i + 1) % corners.count]
            twice += a.x * b.y - b.x * a.y
        }
        let share = abs(twice) / 2 / (imageSize.width * imageSize.height)
        return share >= 0.25 && share <= 0.95
    }
}
