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
    private(set) var volume: Int?
    private(set) var devices: [EchoDevice] = []
    private(set) var alerts: [Alert] = []
    var banner: Banner?

    private var backend: CloudBackend?
    private var pollTask: Task<Void, Never>?
    private var lastAction: Action?

    var selectedDevice: EchoDevice? { devices.first { $0.id == selectedDeviceID } ?? devices.first }
    var nextTimer: Alert? { alerts.first { $0.kind == .timer && ($0.fireDate ?? .distantPast) > .now } }

    
    func restoreSession() async {
        guard let session = await Task.detached(operation: { CredentialStore.load() }).value else { return }
        accountDomain = session.domain
        connect(CloudBackend(session: session))
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
        timerDurations = [:]
        volume = nil
        lastAction = nil
        phase = .idle
        banner = nil
    }

    private func connect(_ backend: CloudBackend) {
        self.backend = backend
        isSignedIn = true
        poll()
    }

    
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
            timerDurations = timerDurations.filter { id, _ in alerts.contains { $0.id == id } }
            if banner?.isError == true, banner?.canRetry == false, banner?.needsSignIn == false { banner = nil }
            return true
        } catch {
            show(error)
            return false
        }
    }

    enum Action {
        case timer(minutes: Int, label: String)
        case alarm(Date, AlarmRepeat)
        case reminder(String, Date)

        var kind: AlertKind {
            switch self {
            case .timer: .timer
            case .alarm: .alarm
            case .reminder: .reminder
            }
        }
    }

    func run(_ action: Action) async {
        guard let backend, let device = selectedDevice, phase != .sending else { return }
        let kind = action.kind
        lastAction = action
        phase = .sending
        banner = Banner(text: "Sending to \(device.name)…", isError: false)
        do {
            let before = Set(alerts.map(\.id))
            var duration: TimeInterval?
            switch action {
            case .timer(let minutes, let label):
                duration = TimeInterval(minutes * 60)
                try await backend.send(command: CommandBuilder.timer(minutes: minutes, label: label), to: device)
            case .alarm(let date, let repeating):
                try await backend.send(command: CommandBuilder.alarm(at: date, repeating: repeating), to: device)
            case .reminder(let text, let date):
                try await backend.createReminder(text, at: date, on: device)
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
        await run(lastAction)
    }

    
    /// Fire-and-report for actions with nothing to verify in Alexa's lists.
    @discardableResult
    private func perform(_ done: String, _ operation: (CloudBackend, EchoDevice) async throws -> Void) async -> Bool {
        guard let backend, let device = selectedDevice, phase != .sending else { return false }
        phase = .sending
        do {
            try await operation(backend, device)
            finish(.success, Banner(text: done, isError: false))
            return true
        } catch {
            show(error)
            finish(.failure, banner)
            return false
        }
    }

    /// Silences a ringing alarm or timer on the selected Echo.
    func stopRinging() async {
        await perform("Stopped \(selectedDevice?.name ?? "Echo")") { try await $0.stop($1) }
    }

    /// Sends any sentence, as if spoken to the Echo. Alexa answers out loud on the device.
    func ask(_ text: String) async {
        await perform("Sent to \(selectedDevice?.name ?? "Echo")") { try await $0.send(command: text, to: $1) }
    }

    // MARK: Volume

    func loadVolume() async {
        guard let backend, let device = selectedDevice else { return }
        do { volume = try await backend.volume(of: device) } catch { show(error) }
    }

    func setVolume(_ value: Int) async {
        volume = value
        await perform("Volume \(value)") { try await $0.setVolume(value, on: $1) }
    }

    func cancel(_ alert: Alert) async {
        guard let backend else { return }
        do {
            try await backend.cancel(alert)
            alerts.removeAll { $0.id == alert.id }
        } catch {
            show(error)
        }
    }

    private func show(_ error: Error) {
        let error = error as? AlexaError ?? .endpointChanged(error.localizedDescription)
        if case .sessionExpired = error {
            signOut()
            banner = Banner(text: error.description, needsSignIn: true)
        } else {
            banner = Banner(text: error.description)
        }
    }
}
