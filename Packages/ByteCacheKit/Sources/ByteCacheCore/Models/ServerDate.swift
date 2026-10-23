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
    /// ByteStash's own forms take a fast path: every snippet has two dates, and a long list has thousands.
    static func parse(_ raw: String) -> Date? {
        if let date = fast(raw) { return date }
        return formatted(raw)
    }

    /// `yyyy-MM-dd HH:mm:ss`, `T` instead of the space, optional fraction, optional `Z`: always UTC.
    /// Anything else (an offset such as +02:00) is left to the formatters.
    static func fast(_ raw: String) -> Date? {
        let u = Array(raw.utf8)
        guard u.count >= 19, u[4] == 0x2D, u[7] == 0x2D, u[10] == 0x20 || u[10] == 0x54, u[13] == 0x3A, u[16] == 0x3A else {
            return nil
        }
        func number(_ from: Int, _ count: Int) -> Int? {
            var value = 0
            for i in from..<(from + count) {
                let digit = Int(u[i]) - 0x30
                guard (0...9).contains(digit) else { return nil }
                value = value * 10 + digit
            }
            return value
        }
        guard let year = number(0, 4), let month = number(5, 2), let day = number(8, 2),
              let hour = number(11, 2), let minute = number(14, 2), let second = number(17, 2),
              (1...12).contains(month), (1...31).contains(day), hour < 24, minute < 60, second < 61 else { return nil }
        var index = 19
        var fraction = 0.0
        if index < u.count, u[index] == 0x2E {
            index += 1
            var scale = 0.1
            let start = index
            while index < u.count, (0x30...0x39).contains(u[index]) {
                fraction += Double(u[index] - 0x30) * scale
                scale /= 10
                index += 1
            }
            guard index > start else { return nil }
        }
        if index < u.count, u[index] == 0x5A { index += 1 }
        guard index == u.count else { return nil }
        // Days since 1970-01-01 for a Gregorian date (Howard Hinnant's days_from_civil).
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        let days = era * 146_097 + dayOfEra - 719_468
        // Reject dates the calendar doesn't have (Feb 30): the day must survive the round trip.
        guard day <= daysIn(month, year) else { return nil }
        let seconds = days * 86_400 + hour * 3_600 + minute * 60 + second
        return Date(timeIntervalSince1970: Double(seconds) + fraction)
    }

    private static func daysIn(_ month: Int, _ year: Int) -> Int {
        switch month {
        case 2: return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    /// Formatters are costly to make, so they're made once. Reading dates with them is thread-safe.
    private nonisolated(unsafe) static let sqlZ = formatter("yyyy-MM-dd HH:mm:ss'Z'")
    private nonisolated(unsafe) static let sql = formatter("yyyy-MM-dd HH:mm:ss")
    private nonisolated(unsafe) static let iso = ISO8601DateFormatter()
    private nonisolated(unsafe) static let isoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions.insert(.withFractionalSeconds)
        return f
    }()

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = format
        return f
    }

    private static func formatted(_ raw: String) -> Date? {
        sqlZ.date(from: raw) ?? sql.date(from: raw) ?? iso.date(from: raw) ?? isoFraction.date(from: raw)
    }
}
