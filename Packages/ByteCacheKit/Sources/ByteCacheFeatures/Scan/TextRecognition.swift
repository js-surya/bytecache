import ByteCacheCore
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
/// If the accurate model fails or finds nothing, the fast one is tried before giving up.
public struct VisionTextRecognizer: TextRecognizing {
    public struct UnreadableImage: Error {}

    /// Reads the lines in an image (or a band of it starting at `top`) at one recognition level.
    typealias LineReader = @Sendable (CGImage, CGFloat, VNRequestTextRecognitionLevel) throws -> [OCRLine]
    private let readLines: LineReader
    /// Accurate mode normally answers in 1–3 s even for long screenshots. A stuck Neural Engine
    /// took ~50 s just to fail, so after this long the fast result is used instead.
    private let accurateTimeLimit: Duration

    public init() {
        readLines = Self.visionLines
        accurateTimeLimit = .seconds(12)
    }

    /// For tests: the real recognizer with another time limit for the accurate model.
    init(accurateTimeLimit: Duration) {
        readLines = Self.visionLines
        self.accurateTimeLimit = accurateTimeLimit
    }

    /// For tests: a fake line reader and time limit.
    init(accurateTimeLimit: Duration = .seconds(12), readLines: @escaping LineReader) {
        self.readLines = readLines
        self.accurateTimeLimit = accurateTimeLimit
    }

    public func recognize(imageData: Data) async throws -> String {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let raw = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw UnreadableImage() }
        let orientation = ((CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])?[kCGImagePropertyOrientation] as? UInt32)
            .flatMap(CGImagePropertyOrientation.init) ?? .up
        let recognizer = self
        let image = try Self.upright(raw, orientation)
        // The accurate model can fail or stall, e.g. while the system rebuilds its Neural Engine models.
        let accurate = Task.detached(priority: .userInitiated) { try recognizer.text(in: image, level: .accurate) }
        var accurateError: (any Error)?
        switch await Self.first(of: accurate, within: accurateTimeLimit) {
        case .success(let text) where !text.isEmpty: return text
        case .failure(let error): accurateError = error
        default: break // nothing found, or too slow
        }
        do {
            return try await Task.detached(priority: .userInitiated) { try recognizer.text(in: image, level: .fast) }.value
        } catch {
            throw accurateError ?? error
        }
    }

    /// The task's result, or nil if it takes longer than `limit` (the task keeps running; Vision can't be cancelled).
    private static func first(of task: Task<String, any Error>, within limit: Duration) async -> Result<String, any Error>? {
        await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)
            Task { once.resume(await task.result) }
            Task {
                try? await Task.sleep(for: limit)
                once.resume(nil)
            }
        }
    }

    /// Recognised code for the whole image at one level.
    func text(in image: CGImage, level: VNRequestTextRecognitionLevel) throws -> String {
        let size = CGSize(width: image.width, height: image.height)
        var lines = try readLines(image, 0, level)
        // Vision's accurate model can return nothing at all for tall images (long screenshots);
        // overlapping bands read reliably.
        if lines.isEmpty || size.height > size.width * 1.5 {
            let banded = try bandedLines(in: image, level: level)
            if banded.count > lines.count { lines = banded }
        }
        return OCRLayout.reconstruct(OCRLayout.pieces(from: lines, imageSize: size))
    }

    /// Lines in `image`, in pixels of the full image (`top` = where this crop starts).
    static func visionLines(in image: CGImage, top: CGFloat, level: VNRequestTextRecognitionLevel) throws -> [OCRLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level
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
    func bandedLines(in image: CGImage, level: VNRequestTextRecognitionLevel) throws -> [OCRLine] {
        let height = image.height, band = max(min(image.width, height), 400), overlap = band / 5
        var result: [OCRLine] = []
        var top = 0
        while top < height {
            let bottom = min(top + band, height)
            guard let crop = image.cropping(to: CGRect(x: 0, y: top, width: image.width, height: bottom - top)) else { break }
            let keepFrom = top == 0 ? 0 : CGFloat(top + overlap / 2)
            let keepTo = bottom == height ? CGFloat(height) : CGFloat(bottom - overlap / 2)
            result += try readLines(crop, CGFloat(top), level).filter {
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

/// Resumes a continuation once; later calls are ignored.
private final class ResumeOnce<T: Sendable>: @unchecked Sendable {
    private var continuation: CheckedContinuation<T, Never>?
    private let lock = NSLock()

    init(_ continuation: CheckedContinuation<T, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: T) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
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
                AppLog.shared.record("scan", "no text found")
                Haptics.play(.error)
                return nil
            }
            Haptics.play(.success)
            AppLog.shared.record("scan", "read \(trimmed.split(separator: "\n").count) lines")
            return trimmed
        } catch {
            self.error = "ByteCache couldn't read that image."
            AppLog.shared.record("scan", "failed: \(type(of: error))")
            Haptics.play(.error)
            return nil
        }
    }
}
