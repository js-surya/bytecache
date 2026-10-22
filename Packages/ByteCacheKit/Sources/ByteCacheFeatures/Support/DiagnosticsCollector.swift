import ByteCacheCore
import Foundation
#if canImport(MetricKit)
import MetricKit

/// Receives the crash and hang reports iOS and macOS collect for ByteCache (MetricKit, usually on
/// the next launch) and keeps the newest few for bug reports. The system makes them: call stacks as
/// binary names and addresses, exception codes, no personal data, and no third-party SDK involved.
public final class DiagnosticsCollector: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    public static let shared = DiagnosticsCollector()

    /// Call once at launch.
    public func start() {
        MXMetricManager.shared.add(self)
        receive(MXMetricManager.shared.pastDiagnosticPayloads)
    }

    public func didReceive(_ payloads: [MXDiagnosticPayload]) {
        receive(payloads)
    }

    private func receive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            var parts: [String] = []
            for crash in payload.crashDiagnostics ?? [] {
                let codes = [Self.exceptionName(crash.exceptionType), Self.signalName(crash.signal)].compactMap { $0 }
                parts.append("crash" + (codes.isEmpty ? "" : " (\(codes.joined(separator: ", ")))"))
            }
            for hang in payload.hangDiagnostics ?? [] {
                parts.append("hang of \(hang.hangDuration.converted(to: .seconds).formatted(.measurement(width: .narrow)))")
            }
            if !(payload.cpuExceptionDiagnostics ?? []).isEmpty { parts.append("too much CPU") }
            if !(payload.diskWriteExceptionDiagnostics ?? []).isEmpty { parts.append("too many disk writes") }
            guard !parts.isEmpty else { continue }
            let summary = parts.joined(separator: ", ")
            CrashWatch.shared.saveDiagnostic(summary: summary, json: payload.jsonRepresentation(), date: payload.timeStampEnd)
            AppLog.shared.record("diagnostics", "system reported: \(summary)")
        }
    }

    private static func exceptionName(_ code: NSNumber?) -> String? {
        guard let code else { return nil }
        return switch code.intValue {
        case 1: "EXC_BAD_ACCESS"
        case 2: "EXC_BAD_INSTRUCTION"
        case 3: "EXC_ARITHMETIC"
        case 6: "EXC_BREAKPOINT"
        case 10: "EXC_CRASH"
        case 11: "EXC_RESOURCE"
        case 12: "EXC_GUARD"
        default: "exception \(code)"
        }
    }

    private static func signalName(_ code: NSNumber?) -> String? {
        guard let code else { return nil }
        return switch code.intValue {
        case 4: "SIGILL"
        case 5: "SIGTRAP"
        case 6: "SIGABRT"
        case 9: "SIGKILL"
        case 10: "SIGBUS"
        case 11: "SIGSEGV"
        default: "signal \(code)"
        }
    }
}
#endif
