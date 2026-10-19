import Foundation

/// Decodes a boolean that the server may send as `true`/`false` or as `1`/`0`.
@propertyWrapper
public struct FlexibleBool: Decodable, Hashable, Sendable {
    public var wrappedValue: Bool

    public init(wrappedValue: Bool) {
        self.wrappedValue = wrappedValue
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            wrappedValue = bool
        } else {
            wrappedValue = try container.decode(Int.self) != 0
        }
    }
}
