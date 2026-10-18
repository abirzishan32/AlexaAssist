import Foundation

enum AlertKind: String, Sendable { case alarm, timer, reminder }

struct EchoDevice: Identifiable, Hashable, Sendable {
    let id: String          // serial number
    let name: String        // "Bedroom Echo Dot"
    let deviceType: String
    let isOnline: Bool
}

struct Alert: Identifiable, Hashable, Sendable {
    let id: String
    let kind: AlertKind
    let deviceID: String
    let fireDate: Date?
    let label: String?
    let repeats: Bool
}

/// The one place user-facing error text lives.
enum AlexaError: Error, CustomStringConvertible {
    case sessionExpired
    case noEchoDevices
    case deviceOffline(String)
    case endpointChanged(String)
    case rateLimited
    case network(Error)

    var description: String {
        switch self {
        case .sessionExpired: "Amazon session expired. Sign in again."
        case .noEchoDevices: "No Echo with timers or alarms found on this Amazon account."
        case .deviceOffline(let name): "\(name) is offline."
        case .endpointChanged(let detail): "Amazon returned something unexpected (\(detail))."
        case .rateLimited: "Amazon is rate limiting. Retrying shortly."
        case .network: "No connection. Retrying automatically."
        }
    }
}
