import Foundation

extension JSONDecoder {
    /// Decoder for ByteStash responses: snake_case keys and the server's date formats.
    public static var byteStash: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            guard let date = ServerDate.parse(raw) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unrecognized date: \(raw)"
                ))
            }
            return date
        }
        return decoder
    }
}

enum ServerDate {
    /// Accepts `yyyy-MM-dd HH:mm:ssZ` (UTC, as sent by ByteStash), then ISO 8601 with or without fractions.
    static func parse(_ raw: String) -> Date? {
        let sql = DateFormatter()
        sql.locale = Locale(identifier: "en_US_POSIX")
        sql.timeZone = TimeZone(identifier: "UTC")
        sql.dateFormat = "yyyy-MM-dd HH:mm:ss'Z'"
        if let date = sql.date(from: raw) { return date }

        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions.insert(.withFractionalSeconds)
        return iso.date(from: raw)
    }
}
