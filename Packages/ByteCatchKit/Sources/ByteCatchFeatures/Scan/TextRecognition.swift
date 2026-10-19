import CoreImage
import Foundation
import ImageIO
import Observation
import Vision

public protocol TextRecognizing: Sendable {
    func recognize(imageData: Data) async throws -> String
}

/// On-device text recognition (Vision), tuned for code: accurate mode, no autocorrect, English
/// only (stops Cyrillic look-alikes), tilted photos straightened, tall screenshots read in bands.
public struct VisionTextRecognizer: TextRecognizing {
    public struct UnreadableImage: Error {}

    public init() {}

    public func recognize(imageData: Data) async throws -> String {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let raw = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw UnreadableImage() }
        let orientation = ((CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])?[kCGImagePropertyOrientation] as? UInt32)
            .flatMap(CGImagePropertyOrientation.init) ?? .up
        return try await Task.detached(priority: .userInitiated) {
            let image = try Self.upright(raw, orientation)
            let size = CGSize(width: image.width, height: image.height)
            var lines = try Self.lines(in: image, top: 0)
            // Vision's accurate model can return nothing at all for tall images (long screenshots);
            // overlapping bands read reliably.
            if lines.isEmpty || size.height > size.width * 1.5 {
                let banded = try Self.bandedLines(in: image)
                if banded.count > lines.count { lines = banded }
            }
            return OCRLayout.reconstruct(OCRLayout.pieces(from: lines, imageSize: size))
        }.value
    }

    /// Lines in `image`, in pixels of the full image (`top` = where this crop starts).
    static func lines(in image: CGImage, top: CGFloat) throws -> [OCRLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        request.automaticallyDetectsLanguage = false
        try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
        let w = CGFloat(image.width), h = CGFloat(image.height)
        // Vision: normalised, origin bottom-left.
        func point(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * w, y: top + (1 - p.y) * h) }
        return (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string else { return nil }
            return OCRLine(text: text, topLeft: point(observation.topLeft), topRight: point(observation.topRight),
                           bottomLeft: point(observation.bottomLeft), bottomRight: point(observation.bottomRight))
        }
    }

    /// Square-ish bands overlapping by a fifth; each line is kept from the band whose middle part holds it.
    static func bandedLines(in image: CGImage) throws -> [OCRLine] {
        let height = image.height, band = max(min(image.width, height), 400), overlap = band / 5
        var result: [OCRLine] = []
        var top = 0
        while top < height {
            let bottom = min(top + band, height)
            guard let crop = image.cropping(to: CGRect(x: 0, y: top, width: image.width, height: bottom - top)) else { break }
            let keepFrom = top == 0 ? 0 : CGFloat(top + overlap / 2)
            let keepTo = bottom == height ? CGFloat(height) : CGFloat(bottom - overlap / 2)
            result += try lines(in: crop, top: CGFloat(top)).filter {
                let mid = ($0.topLeft.y + $0.bottomLeft.y) / 2
                return mid >= keepFrom && mid < keepTo
            }
            if bottom == height { break }
            top = bottom - overlap
        }
        return result
    }

    /// Applies the photo's EXIF orientation so coordinates match what the user sees.
    static func upright(_ image: CGImage, _ orientation: CGImagePropertyOrientation) throws -> CGImage {
        guard orientation != .up else { return image }
        let turned = CIImage(cgImage: image).oriented(orientation)
        guard let result = CIContext().createCGImage(turned, from: turned.extent) else { throw UnreadableImage() }
        return result
    }
}

/// Runs recognition for the scan flow and turns failures into messages.
@MainActor @Observable
public final class ScanCodeModel {
    public private(set) var isRecognizing = false
    public var error: String?

    private let recognizer: any TextRecognizing

    public init(recognizer: any TextRecognizing = VisionTextRecognizer()) {
        self.recognizer = recognizer
    }

    /// The recognised code, or nil with `error` set.
    public func recognize(imageData: Data) async -> String? {
        isRecognizing = true
        error = nil
        defer { isRecognizing = false }
        do {
            let text = try await recognizer.recognize(imageData: imageData)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : text
                .replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
            guard !trimmed.isEmpty else {
                error = "No text found in that image. Try a sharper, closer shot."
                return nil
            }
            return trimmed
        } catch {
            self.error = "ByteCatch couldn't read that image."
            return nil
        }
    }
}
