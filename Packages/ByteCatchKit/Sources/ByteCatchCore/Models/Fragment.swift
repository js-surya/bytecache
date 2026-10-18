import Foundation

public struct Fragment: Codable, Hashable, Sendable, Identifiable {
    public var id: Int { serverID ?? position }
    /// Server-assigned id; nil for fragments that were never saved.
    public let serverID: Int?
    public var fileName: String
    public var code: String
    public var language: String
    public var position: Int

    public init(id: Int?, fileName: String, code: String, language: String, position: Int) {
        self.serverID = id
        self.fileName = fileName
        self.code = code
        self.language = language
        self.position = position
    }

    private enum CodingKeys: String, CodingKey {
        case serverID = "id", fileName, code, language, position
    }
}
