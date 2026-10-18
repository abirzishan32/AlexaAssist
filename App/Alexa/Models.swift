import Foundation

enum AlertKind: String, Codable, Sendable { case alarm, timer, reminder }

struct EchoDevice: Identifiable, Hashable, Codable, Sendable {
    let id: String          // serial number
    let name: String        // "Bedroom Echo Dot"
    let deviceType: String
    let isOnline: Bool
}

struct Alert: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let kind: AlertKind
    let deviceID: String
    let fireDate: Date?
    let label: String?
    let repeats: Bool
}

protocol AlexaBackend: Sendable {
    func devices() async throws -> [EchoDevice]
    func send(command: String, to device: EchoDevice) async throws
    func createReminder(_ text: String, at date: Date, on device: EchoDevice) async throws
    func upcomingAlerts() async throws -> [Alert]
    func cancel(_ alert: Alert) async throws
}

enum AlexaError: Error, CustomStringConvertible {
    case sessionExpired
    case noEchoDevices
    case deviceOffline(String)
    case endpointChanged(String)
    case rateLimited
    case network(Error)

    var description: String {
        switch self {
        case .sessionExpired: "Amazon session expired"
        case .noEchoDevices: "No Echo with timers/alarms found on this Amazon account"
        case .deviceOffline(let name): "\(name) is offline"
        case .endpointChanged(let detail): "Amazon returned something unexpected (\(detail))"
        case .rateLimited: "Amazon is rate limiting"
        case .network(let error): "No connection (\(error.localizedDescription))"
        }
    }
}
