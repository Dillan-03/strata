import Foundation

/// Helpers for values produced by `JSONSerialization`, which bridges numbers to `Bool` on some platforms.
enum JSONValue {
    /// True only for JSON `true`/`false`, never for `0` or `1`.
    static func isBoolean(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber else { return false }
        return String(cString: number.objCType) == "c"
    }

    static func bool(_ value: Any?) -> Bool? {
        guard isBoolean(value), let number = value as? NSNumber else { return nil }
        return number.boolValue
    }

    static func string(_ value: Any?) -> String? {
        value as? String
    }

    static func strings(_ value: Any?) -> [String]? {
        guard let array = value as? [Any] else { return nil }
        return array.compactMap { $0 as? String }
    }

    static func stringMap(_ value: Any?) -> [String: String]? {
        guard let dictionary = value as? [String: Any] else { return nil }
        var result: [String: String] = [:]
        for (key, element) in dictionary {
            if let string = element as? String {
                result[key] = string
            } else if let number = element as? NSNumber {
                result[key] = isBoolean(number) ? (number.boolValue ? "true" : "false") : number.stringValue
            }
        }
        return result
    }
}
