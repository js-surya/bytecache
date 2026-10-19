import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Vision
import XCTest
@testable import ByteCacheFeatures

/// CP-20: when Vision's accurate recognizer fails, the fast one is tried before giving up.
final class OCRFallbackTests: XCTestCase {
    struct NeuralEngineFailure: Error {}

    /// Any valid image will do; the line reader is faked.
    private func png() throws -> Data {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 400, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let data = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, try XCTUnwrap(ctx.makeImage()), nil)
        CGImageDestinationFinalize(dest)
        return data as Data
    }

    private static func line(_ text: String) -> OCRLine {
        OCRLine(text: text, topLeft: CGPoint(x: 10, y: 10), topRight: CGPoint(x: 200, y: 10),
                bottomLeft: CGPoint(x: 10, y: 40), bottomRight: CGPoint(x: 200, y: 40))
    }

    func testFastRecognitionIsUsedWhenAccurateThrows() async throws {
        let recognizer = VisionTextRecognizer { _, _, level in
            if level == .accurate { throw NeuralEngineFailure() }
            return [Self.line("print(1)")]
        }
        let text = try await recognizer.recognize(imageData: try png())
        XCTAssertEqual(text, "print(1)")
    }

    func testFastRecognitionIsTriedWhenAccurateFindsNothing() async throws {
        let recognizer = VisionTextRecognizer { _, _, level in level == .accurate ? [] : [Self.line("ls -la")] }
        let text = try await recognizer.recognize(imageData: try png())
        XCTAssertEqual(text, "ls -la")
    }

    func testErrorWhenBothFail() async throws {
        let recognizer = VisionTextRecognizer { _, _, _ in throw NeuralEngineFailure() }
        do {
            _ = try await recognizer.recognize(imageData: try png())
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue(error is NeuralEngineFailure)
        }
    }

    func testAccurateResultWinsWhenItWorks() async throws {
        let recognizer = VisionTextRecognizer { _, _, level in [Self.line(level == .accurate ? "accurate" : "fast")] }
        let text = try await recognizer.recognize(imageData: try png())
        XCTAssertEqual(text, "accurate")
    }

    /// A stuck accurate model (it took ~50 s to fail while macOS rebuilt its Neural Engine models)
    /// must not keep the user waiting: after the time limit the fast result is used.
    func testFastResultIsUsedWhenAccurateIsTooSlow() async throws {
        let recognizer = VisionTextRecognizer(accurateTimeLimit: .milliseconds(200)) { _, _, level in
            if level == .accurate {
                Thread.sleep(forTimeInterval: 2)
                return [Self.line("accurate")]
            }
            return [Self.line("fast")]
        }
        let started = Date()
        let text = try await recognizer.recognize(imageData: try png())
        XCTAssertEqual(text, "fast")
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.5)
    }
}
