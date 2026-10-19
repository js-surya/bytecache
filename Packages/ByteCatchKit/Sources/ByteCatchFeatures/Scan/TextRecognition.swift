import Foundation
import ImageIO
import Observation
import Vision

public protocol TextRecognizing: Sendable {
    func recognize(imageData: Data) async throws -> String
}

/// On-device text recognition (Vision), tuned for code: accurate mode, no autocorrect.
public struct VisionTextRecognizer: TextRecognizing {
    public struct UnreadableImage: Error {}

    public init() {}

    public func recognize(imageData: Data) async throws -> String {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw UnreadableImage() }
        let orientation = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])?[kCGImagePropertyOrientation] as? UInt32
        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: image, orientation: orientation.flatMap(CGImagePropertyOrientation.init) ?? .up)
            try handler.perform([request])
            let pieces = (request.results ?? []).compactMap { observation -> OCRPiece? in
                guard let text = observation.topCandidates(1).first?.string else { return nil }
                let box = observation.boundingBox // normalised, origin bottom-left
                return OCRPiece(text: text, minX: box.minX, minY: 1 - box.maxY, width: box.width, height: box.height)
            }
            return OCRLayout.reconstruct(pieces)
        }.value
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
