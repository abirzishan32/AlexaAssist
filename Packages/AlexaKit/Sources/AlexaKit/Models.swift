import Foundation

public enum AlertKind: String, Codable, Sendable { case alarm, timer, reminder }

public struct EchoDevice: Identifiable, Hashable, Codable, Sendable {
    public let id: String          // serial number
    public let name: String        // "Bedroom Echo Dot"
    public let deviceType: String
    public let isOnline: Bool
}

public struct Alert: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let kind: AlertKind
    public let deviceID: String
    public let fireDate: Date?
    public let label: String?
    public let repeats: Bool
}

public protocol AlexaBackend: Sendable {
    func devices() async throws -> [EchoDevice]
    func send(command: String, to device: EchoDevice) async throws
    func createReminder(_ text: String, at date: Date, on device: EchoDevice) async throws
    func upcomingAlerts() async throws -> [Alert]
    func cancel(_ alert: Alert) async throws
}

public enum AlexaError: Error, CustomStringConvertible {
    case sessionExpired
    case noEchoDevices
    case deviceOffline(String)
    case endpointChanged(String)
    case rateLimited
    case network(Error)

    public var description: String {
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
