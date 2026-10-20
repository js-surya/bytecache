import Foundation

/// What this installed copy was really signed with. Release builds are unsigned and get re-signed
/// when sideloaded (AltStore, SideStore, Sideloadly…), which renames the App Group and changes the
/// team prefix, so the IDs written into Info.plist at build time may not be the ones that work.
public struct InstallSigning: Equatable, Sendable {
    /// App Groups granted to this copy (no wildcards).
    public var appGroups: [String]
    /// Team / App ID prefix of the signing identity, e.g. "ABCDE12345".
    public var teamPrefix: String?

    public init(appGroups: [String] = [], teamPrefix: String? = nil) {
        self.appGroups = appGroups
        self.teamPrefix = teamPrefix
    }

    /// Reads `embedded.mobileprovision` (a signed plist) and AltStore/SideStore's `ALTAppGroups` key.
    public static func current(bundle: Bundle = .main) -> InstallSigning {
        var signing = bundle.url(forResource: "embedded", withExtension: "mobileprovision")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap(profile) ?? InstallSigning()
        let altGroups = bundle.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] ?? []
        signing.appGroups = altGroups + signing.appGroups.filter { !altGroups.contains($0) }
        return signing
    }

    /// Parses the plist inside a provisioning profile's signature envelope.
    static func profile(_ data: Data) -> InstallSigning? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(from: data[start.lowerBound..<end.upperBound], format: nil)
                as? [String: Any] else { return nil }
        let entitlements = plist["Entitlements"] as? [String: Any] ?? [:]
        let groups = (entitlements["com.apple.security.application-groups"] as? [String] ?? []).filter { !$0.contains("*") }
        let prefix = (plist["ApplicationIdentifierPrefix"] as? [String])?.first
            ?? (plist["TeamIdentifier"] as? [String])?.first
        return InstallSigning(appGroups: groups, teamPrefix: prefix)
    }

    /// The App Group to use: the declared one when it works, otherwise the one this copy was given
    /// (preferring ByteCache's own). `isUsable` checks the group's container exists.
    public func appGroup(declared: String?, isUsable: (String) -> Bool) -> String? {
        let given = appGroups.sorted { a, b in
            a.localizedCaseInsensitiveContains("bytecache") && !b.localizedCaseInsensitiveContains("bytecache")
        }
        return ([declared].compactMap { $0 } + given).first(where: isUsable)
    }

    /// The shared keychain group with this copy's team prefix. Unsigned builds have no prefix in
    /// Info.plist ("app.bytecache.shared"), and re-signing changes it.
    public func keychainGroup(declared: String?) -> String? {
        guard let declared else { return nil }
        guard let teamPrefix else { return declared }
        let parts = declared.split(separator: ".", maxSplits: 1)
        let hasPrefix = parts.count == 2 && parts[0].count == 10 && parts[0].allSatisfy { $0.isUppercase || $0.isNumber }
        let name = hasPrefix ? String(parts[1]) : declared
        return "\(teamPrefix).\(name)"
    }
}
