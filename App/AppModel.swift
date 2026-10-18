import AlexaKit
import Foundation
import Observation

@Observable @MainActor
final class AppModel {
    struct Banner: Equatable {
        var text: String
        var isError = true
        var canRetry = false
        var needsSignIn = false
    }

    enum Phase { case idle, sending, success, failure }

    private(set) var accountDomain: String?
    private(set) var phase = Phase.idle
    /// Total length of timers started here, so the UI can draw progress (Alexa only reports the end time).
    private(set) var timerDurations: [String: TimeInterval] = [:]
    @ObservationIgnored var openSignIn: () -> Void = {}
    @ObservationIgnored var openSettings: () -> Void = {}
    var selectedDeviceID = UserDefaults.standard.string(forKey: "device") {
        didSet { UserDefaults.standard.set(selectedDeviceID, forKey: "device") }
    }
    var isPanelOpen = false {
        didSet { if isPanelOpen && !oldValue && isSignedIn { poll() } }
    }
    private(set) var isSignedIn = false
    private(set) var devices: [EchoDevice] = []
    private(set) var alerts: [AlexaKit.Alert] = []
    var banner: Banner?

    private var backend: (any AlexaBackend)?
    private var pollTask: Task<Void, Never>?
    private var lastAction: (action: Action, duration: TimeInterval?)?

    var selectedDevice: EchoDevice? { devices.first { $0.id == selectedDeviceID } ?? devices.first }
    var nextTimer: AlexaKit.Alert? { alerts.first { $0.kind == .timer && ($0.fireDate ?? .distantPast) > .now } }

    init() {
        if let session = CredentialStore.load() {
            accountDomain = session.domain
            connect(CloudBackend(session: session))
        }
    }

    func signedIn(_ session: AmazonSession) {
        do { try CredentialStore.save(session) } catch {
            banner = Banner(text: "Couldn't save to Keychain. You'll need to sign in again next launch.")
        }
        accountDomain = session.domain
        connect(CloudBackend(session: session))
    }

    func signOut() {
        pollTask?.cancel()
        CredentialStore.delete()
        backend = nil
        accountDomain = nil
        isSignedIn = false
        devices = []
        alerts = []
        banner = nil
    }

    private func connect(_ backend: any AlexaBackend) {
        self.backend = backend
        isSignedIn = true
        poll()
    }

    /// Refreshes now (devices too), then every 60 s while the panel is open / 5 min otherwise.
    /// Backs off on errors, and wakes when the next timer fires so the menu bar countdown never sits at 0:00.
    private func poll() {
        pollTask?.cancel()
        pollTask = Task {
            var withDevices = true
            var backoff: Double = 0
            while !Task.isCancelled, isSignedIn {
                backoff = await refresh(devices: withDevices) ? 0 : min(max(backoff * 2, 15), 900)
                withDevices = devices.isEmpty
                var delay = backoff > 0 ? backoff : isPanelOpen ? 60 : 300
                if let fire = nextTimer?.fireDate { delay = min(delay, max(1, fire.timeIntervalSinceNow + 1)) }
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    private func refresh(devices withDevices: Bool) async -> Bool {
        guard let backend else { return false }
        do {
            if withDevices { devices = try await backend.devices() }
            alerts = try await backend.upcomingAlerts()
            if banner?.isError == true, banner?.canRetry == false, banner?.needsSignIn == false { banner = nil }
            return true
        } catch {
            show(error)
            return false
        }
    }

    enum Action {
        case say(String)                 // spoken-style command (timers, alarms)
        case reminder(String, Date)      // created directly, so text and time can't get lost

        var kind: AlertKind {
            switch self {
            case .say(let text): text.contains("timer") ? .timer : .alarm
            case .reminder: .reminder
            }
        }
    }

    /// Sends the action, then waits for the new item to show up in Alexa's list before claiming success.
    func run(_ action: Action, duration: TimeInterval? = nil) async {
        guard let backend, let device = selectedDevice, phase != .sending else { return }
        let kind = action.kind
        lastAction = (action, duration)
        phase = .sending
        banner = Banner(text: "Sending to \(device.name)…", isError: false)
        do {
            let before = Set(alerts.map(\.id))
            switch action {
            case .say(let command): try await backend.send(command: command, to: device)
            case .reminder(let text, let date): try await backend.createReminder(text, at: date, on: device)
            }
            for wait in [2, 3] {
                try await Task.sleep(for: .seconds(wait))
                alerts = try await backend.upcomingAlerts()
                if let new = alerts.first(where: { $0.kind == kind && !before.contains($0.id) }) {
                    if let duration { timerDurations[new.id] = duration }
                    let done = switch kind {
                    case .timer: "Timer started"
                    case .alarm: "Alarm set"
                    case .reminder: "Reminder set"
                    }
                    finish(.success, Banner(text: done, isError: false))
                    return
                }
            }
            finish(.failure, Banner(text: "Alexa didn't confirm it. Check the Alexa app.", canRetry: true))
        } catch {
            show(error)
            if banner?.needsSignIn == false { banner?.canRetry = true }
            finish(.failure, banner)
        }
    }

    /// Success messages fade after a few seconds; errors stay until something succeeds.
    private func finish(_ phase: Phase, _ banner: Banner?) {
        self.phase = phase
        self.banner = banner
        Task {
            try? await Task.sleep(for: .seconds(3))
            if self.phase == phase { self.phase = .idle }
            if let banner, !banner.isError, self.banner == banner { self.banner = nil }
        }
    }

    func retry() async {
        guard let lastAction else { return }
        await run(lastAction.action, duration: lastAction.duration)
    }

    func cancel(_ alert: AlexaKit.Alert) async {
        guard let backend else { return }
        do {
            try await backend.cancel(alert)
            alerts.removeAll { $0.id == alert.id }
        } catch {
            show(error)
        }
    }

    private func show(_ error: Error) {
        switch error as? AlexaError {
        case .sessionExpired?:
            signOut()
            banner = Banner(text: "Session expired", needsSignIn: true)
        case .noEchoDevices?:
            banner = Banner(text: "No Echo with alarms found on this Amazon account")
        case .deviceOffline(let name)?:
            banner = Banner(text: "\(name) is offline")
        case .endpointChanged?:
            banner = Banner(text: "\(error)")
        case .rateLimited?:
            banner = Banner(text: "Amazon is rate limiting. Retrying shortly.")
        case .network?, nil:
            banner = Banner(text: "No connection. Retrying automatically.")
        }
    }
}
