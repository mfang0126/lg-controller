import Foundation

enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .number(Double(value))
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let value):
            return value
        case .string(let value):
            switch value.lowercased() {
            case "true", "yes", "on", "1": return true
            case "false", "no", "off", "0": return false
            default: return nil
            }
        case .number(let value):
            return value == 1 ? true : value == 0 ? false : nil
        default:
            return nil
        }
    }

    var integerValue: Int? {
        switch self {
        case .number(let value):
            return Int(value)
        case .string(let value):
            return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }
}

struct WebOSMessage: Codable, Equatable {
    let type: String
    let id: String?
    let uri: String?
    let payload: [String: JSONValue]?

    init(
        type: String,
        id: String? = nil,
        uri: String? = nil,
        payload: [String: JSONValue]? = nil
    ) {
        self.type = type
        self.id = id
        self.uri = uri
        self.payload = payload
    }

    func jsonData() throws -> Data {
        try JSONEncoder().encode(self)
    }

    func payloadValue(_ key: String) -> JSONValue? {
        payload?[key]
    }
}

enum WebOSURIs {
    static let getVolume = "ssap://audio/getVolume"
    static let volumeUp = "ssap://audio/volumeUp"
    static let volumeDown = "ssap://audio/volumeDown"
    static let setMute = "ssap://audio/setMute"
    static let register = "ssap://pairing/register"
}

struct WebOSPairingMessage: Equatable {
    let message: String
    let clientKey: String?

    init?(message: WebOSMessage) {
        let normalizedType = message.type.lowercased()
        guard normalizedType == "prompt" || normalizedType == "pairing" || normalizedType == "pairingprompt" else {
            return nil
        }

        let payload = message.payload ?? [:]
        let prompt = payload["message"]?.stringValue
            ?? payload["prompt"]?.stringValue
            ?? payload["pairingMessage"]?.stringValue
            ?? "Approve the LG webOS pairing request on the TV."
        self.message = prompt
        self.clientKey = payload["client-key"]?.stringValue
    }
}

enum WebOSRegistration {
    // webOS uses the manifest identity when deciding which pairing key to return.
    // Keep it aligned with the app and CLI Keychain namespace above.
    static let manifest: JSONValue = .object([
        "manifestVersion": .number(1),
        "appVersion": .string(ProductConfiguration.releaseVersion),
        "signed": .object([
            "appId": .string(ProductConfiguration.bundleIdentifier),
            "created": .string("2026-09-15"),
            "vendorId": .string(ProductConfiguration.webOSVendorIdentifier),
            "localizedAppNames": .object(["": .string(ProductConfiguration.displayName)]),
            "localizedVendorNames": .object(["": .string(ProductConfiguration.displayName)]),
            "permissions": .array([
                .string("CONTROL_AUDIO"),
                .string("READ_AUDIO_VOLUME")
            ])
        ]),
        // webOS grants SSAP capabilities from this top-level list.
        "permissions": .array([
            .string("CONTROL_AUDIO"),
            .string("READ_AUDIO_VOLUME")
        ])
    ])
}
