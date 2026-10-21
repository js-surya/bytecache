import Foundation

/// Product copy shared across platforms.
public enum AboutText {
    public static let appName = "ByteCache"
    public static let tagline = "Cache the bytes"
    /// Says what the app is for, where the tagline alone wouldn't (first launch).
    public static let purpose = "A client for your ByteStash server"
    public static let privacy = "ByteCache collects no data."
    public static let credit = "Made with ❤️ by SyntaxError"
    /// The project's source code (the About footer shows no account name).
    public static let sourceCode = URL(string: "https://github.com/js-surya/bytecache")!
    public static let contactEmail = "hello@suryajs.me"
    /// Tips (GitHub and Xcode copies only: App Store apps may not link to outside tip pages).
    public static let support = URL(string: "https://ko-fi.com/trailingfox")!
    public static let contact = URL(string: "mailto:\(contactEmail)")!
    public static let disclaimer = "ByteCache is not affiliated with the ByteStash project."

    /// What people see: "1.1.0".
    public static var displayVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    /// With the build number, for bug reports: "1.1.0 (12)".
    public static var versionWithBuild: String {
        "\(displayVersion) (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))"
    }
}
