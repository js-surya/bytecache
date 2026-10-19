import Foundation

/// Product copy shared across platforms.
public enum AboutText {
    public static let appName = "ByteCache"
    public static let tagline = "Cache the bytes"
    /// Says what the app is for, where the tagline alone wouldn't (first launch).
    public static let purpose = "A client for your ByteStash server"
    public static let privacy = "ByteCache collects no data."
    public static let credit = "Built with ❤️ by SyntaxError and Claude"
    public static let developerGitHub = URL(string: "https://github.com/js-surya")!

    /// What people see: "1.1.0".
    public static var displayVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    /// With the build number, for bug reports: "1.1.0 (12)".
    public static var versionWithBuild: String {
        "\(displayVersion) (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))"
    }
}
