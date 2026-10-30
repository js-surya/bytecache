import CoreGraphics
import Foundation
import ImageIO
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Fix Scan: a model that can see pictures compares the recognised code with the photo and corrects
/// what text recognition got wrong (look-alike characters, lost brackets, indentation). Runs only when
/// the person taps Fix with AI, so with their own provider the picture is sent only then.
public protocol ScanFixer: Sendable {
    func fix(code: String, jpeg: Data) async throws -> String
}

public enum ScanFix {
    public struct TooDifferent: LocalizedError {
        public var errorDescription: String? { "The AI's version was too different from the scan, so the scan was kept." }
    }

    static let instructions = """
    You correct code that text recognition (OCR) read from the attached picture. Compare the text with \
    the picture and fix recognition mistakes only: wrong or look-alike characters (0/O, 1/l/I, quotes), \
    missing or extra brackets, braces, quotes and punctuation, broken indentation and wrongly joined or \
    split lines. Keep everything else exactly as it is: don't rename, reformat, complete or improve the \
    code, and don't add comments. Reply with only the corrected code, without Markdown fences or explanations.
    """

    static func prompt(for code: String) -> String {
        "Code read by OCR:\n\(code)"
    }

    /// The model's answer without Markdown fences, or nil when it's empty or changed too much to trust.
    static func cleaned(_ answer: String, original: String) -> String? {
        var text = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            var lines = text.components(separatedBy: "\n")
            lines.removeFirst()
            if lines.last?.trimmingCharacters(in: .whitespaces).hasPrefix("```") == true { lines.removeLast() }
            text = lines.joined(separator: "\n")
        }
        text = text.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
        guard !text.isEmpty else { return nil }
        let ratio = Double(text.count) / Double(max(original.count, 1))
        return (0.6...1.6).contains(ratio) ? text : nil
    }

    /// The photo made smaller for sending: at most `maxSide` pixels on the long side, JPEG.
    static func jpeg(_ data: Data, maxSide: Int = 2_048) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: maxSide]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return jpegData(image)
    }

    static func jpegData(_ image: CGImage, quality: Double = 0.85) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    /// Apple Intelligence when it can see pictures (iOS / macOS 27 on supported devices).
    public static func onDevice() -> (any ScanFixer)? {
        #if canImport(FoundationModels)
        if #available(iOS 27.0, macOS 27.0, *), case .available = SystemLanguageModel.default.availability,
           SystemLanguageModel.default.capabilities.contains(.vision) {
            return AppleIntelligenceScanFixer()
        }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
@available(iOS 27.0, macOS 27.0, *)
struct AppleIntelligenceScanFixer: ScanFixer {
    func fix(code: String, jpeg: Data) async throws -> String {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw VisionTextRecognizer.UnreadableImage() }
        let session = LanguageModelSession(instructions: ScanFix.instructions)
        let answer = try await session.respond {
            ScanFix.prompt(for: code)
            Attachment(image)
        }.content
        guard let fixed = ScanFix.cleaned(answer, original: code) else { throw ScanFix.TooDifferent() }
        return fixed
    }
}
#endif

/// Fix Scan with the person's own provider; the model must accept pictures.
public struct RemoteScanFixer: ScanFixer {
    let client: RemoteAIClient

    public init(client: RemoteAIClient) { self.client = client }

    public func fix(code: String, jpeg: Data) async throws -> String {
        let answer = try await client.complete(system: ScanFix.instructions, prompt: ScanFix.prompt(for: code), jpeg: jpeg)
        guard let fixed = ScanFix.cleaned(answer, original: code) else { throw ScanFix.TooDifferent() }
        return fixed
    }
}
