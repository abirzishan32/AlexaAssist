import Foundation
import OSLog

/// Talks to the Alexa web API (alexa.<domain>) with the user's own session. All requests go through this
/// actor; concurrent callers share one in-flight cookie refresh.
actor CloudBackend {
    private let refreshToken: String
    private let domain: String
    private let customerID: String
    private let base: URL
    // Cookies are handled by hand: a private in-memory jar, never the shared one, and no URLSession magic.
    private let http: URLSession
    private var cookies: [String: String] = [:]
    private var auth: Task<String?, Error>?  // resolves to the csrf token
    private let log = Logger(subsystem: "dev.alexaassist", category: "network")

    init(session: AmazonSession) {
        self.init(refreshToken: session.refreshToken, domain: session.domain, customerID: session.customerID)
    }

    init(refreshToken: String, domain: String, customerID: String) {
        self.refreshToken = refreshToken
        self.domain = domain
        self.customerID = customerID
        base = URL(string: "https://alexa.\(domain)")!
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        http = URLSession(configuration: config)
    }

    /// Commands are English, so the locale is the English variant for the account's country.
    var locale: String {
        switch domain {
        case "amazon.co.uk": "en-GB"
        case "amazon.in": "en-IN"
        case "amazon.ca": "en-CA"
        case "amazon.com.au": "en-AU"
        default: "en-US"
        }
    }

    // MARK: - Sign-in helpers

    /// `alexa.amazon.com/api/welcome` names the Alexa host the account really lives on.
    func alexaDomain() async throws -> String {
        let json = try JSONSerialization.jsonObject(with: await call("GET", "/api/welcome"))
        guard let host = dig(json, "alexaHostName") as? String, host.hasPrefix("alexa.") else { return domain }
        return String(host.dropFirst("alexa.".count))
    }

    func accountCustomerID() async throws -> String {
        let json = try JSONSerialization.jsonObject(with: await call("GET", "/api/users/me?platform=ios&version=\(Amazon.appVersion)"))
        guard let id = dig(json, "id") as? String else { throw AlexaError.endpointChanged("users/me: no id") }
        return id
    }

    // MARK: - Alexa API

    func devices() async throws -> [EchoDevice] {
        let dto: DevicesDTO = try decode(await call("GET", "/api/devices-v2/device?cached=false"))
        let echos = (dto.devices ?? []).compactMap(\.echoDevice)
        if echos.isEmpty { throw AlexaError.noEchoDevices }
        return echos
    }

    func send(command: String, to device: EchoDevice) async throws {
        try await runOperation("Alexa.TextCommand", on: device, extra: [
            "skillId": "amzn1.ask.1p.tellalexa", "text": command.lowercased(),
        ])
    }

    /// Silences whatever is ringing or playing on the device (a sounding alarm or timer).
    func stop(_ device: EchoDevice) async throws {
        try await runOperation("Alexa.DeviceControls.Stop", on: device, extra: [
            "skillId": "amzn1.ask.1p.alexadevicecontrols",
            "devices": [["deviceSerialNumber": device.id, "deviceType": device.deviceType]],
        ])
    }

    // MARK: Volume (aioamazondevices implementation/media.py and sequence.py)

    func setVolume(_ volume: Int, on device: EchoDevice) async throws {
        try await runOperation("Alexa.DeviceControls.Volume", on: device, extra: ["value": String(min(100, max(0, volume)))])
    }

    func volume(of device: EchoDevice) async throws -> Int? {
        let json = try JSONSerialization.jsonObject(with: await call("GET", "/api/devices/deviceType/dsn/audio/v1/allDeviceVolumes"))
        let volumes = dig(json, "volumes") as? [[String: Any]] ?? []
        return volumes.first { $0["dsn"] as? String == device.id }?["speakerVolume"] as? Int
    }

    /// One behaviors/preview call with a single operation node (aioamazondevices' `_build_operation_node`).
    private func runOperation(_ type: String, on device: EchoDevice, extra: [String: Any]) async throws {
        guard device.isOnline else { throw AlexaError.deviceOffline(device.name) }
        let payload: [String: Any] = [
            "deviceType": device.deviceType, "deviceSerialNumber": device.id,
            "locale": locale, "customerId": customerID,
        ].merging(extra) { $1 }
        let sequence: [String: Any] = [
            "@type": "com.amazon.alexa.behaviors.model.Sequence",
            "startNode": [
                "@type": "com.amazon.alexa.behaviors.model.SerialNode",
                "nodesToExecute": [[
                    "@type": "com.amazon.alexa.behaviors.model.OpaquePayloadOperationNode",
                    "type": type,
                    "operationPayload": payload,
                ]],
            ],
        ]
        let body: [String: Any] = [
            "behaviorId": "PREVIEW",
            "sequenceJson": String(decoding: try JSONSerialization.data(withJSONObject: sequence), as: UTF8.self),
            "status": "ENABLED",
        ]
        _ = try await call("POST", "/api/behaviors/preview", body: JSONSerialization.data(withJSONObject: body))
    }

    /// alexa-remote2's createNotificationObject + createNotification: the reminder text and time go in
    /// directly, so Alexa never has to ask "when should I remind you?".
    func createReminder(_ text: String, at date: Date, on device: EchoDevice) async throws {
        guard device.isOnline else { throw AlexaError.deviceOffline(device.name) }
        let body = try JSONSerialization.data(withJSONObject: Self.reminderPayload(text, at: date, on: device, now: .now))
        _ = try await call("PUT", "/api/notifications/null", body: body)
    }

    static func reminderPayload(_ text: String, at date: Date, on device: EchoDevice, now: Date) -> [String: Any] {
        let day = DateFormatter(), time = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        time.locale = day.locale
        day.dateFormat = "yyyy-MM-dd"
        time.dateFormat = "HH:mm:ss.000"
        return [
            "alarmTime": Int(date.timeIntervalSince1970 * 1000),
            "createdDate": Int(now.timeIntervalSince1970 * 1000),
            "type": "Reminder",
            "deviceSerialNumber": device.id,
            "deviceType": device.deviceType,
            "reminderLabel": text,
            "timerLabel": NSNull(),
            "sound": NSNull(),
            "originalDate": day.string(from: date),
            "originalTime": time.string(from: date),
            "id": NSNull(),
            "isRecurring": false,
            "recurringPattern": NSNull(),
            "timeZoneId": NSNull(),
            "reminderIndex": NSNull(),
            "isSaveInFlight": true,
            "status": "ON",
        ]
    }

    func upcomingAlerts() async throws -> [Alert] {
        let dto: NotificationsDTO = try decode(await call("GET", "/api/notifications"))
        return dto.alerts(now: .now)
    }

    /// alexa-remote2's deleteNotification: DELETE with the notification's own JSON as the body.
    func cancel(_ alert: Alert) async throws {
        let json = try JSONSerialization.jsonObject(with: await call("GET", "/api/notifications"))
        guard let list = dig(json, "notifications") as? [[String: Any]],
              let item = list.first(where: { $0["id"] as? String == alert.id }) else { return }  // already gone
        let id = alert.id.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(.init(charactersIn: "-_.")))!
        _ = try await call("DELETE", "/api/notifications/\(id)", body: JSONSerialization.data(withJSONObject: item))
    }

    // MARK: - HTTP

    private func call(_ method: String, _ path: String, body: Data? = nil, retried: Bool = false) async throws -> Data {
        let csrf = try await csrf()
        var req = URLRequest(url: URL(string: path, relativeTo: base)!)
        req.httpMethod = method
        req.httpBody = body
        req.setValue(csrf, forHTTPHeaderField: "csrf")
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Accept")
        req.setValue(base.absoluteString, forHTTPHeaderField: "Origin")
        req.setValue(base.absoluteString + "/spa/index.html", forHTTPHeaderField: "Referer")
        let (data, status) = try await load(req)
        // Notification IDs embed the Echo's serial number: keep them out of logs and error text.
        let endpoint = "\(method) " + path.split(separator: "?")[0]
            .replacingOccurrences(of: #"/notifications/.+"#, with: "/notifications/{id}", options: .regularExpression)
        log.info("\(endpoint, privacy: .public) → \(status)")
        switch status {
        case 200..<300:
            return data
        case 401, 403:
            guard !retried else { throw AlexaError.sessionExpired }
            auth = nil  // re-mint cookies once, then give up
            return try await call(method, path, body: body, retried: true)
        case 429:
            throw AlexaError.rateLimited
        default:
            throw AlexaError.endpointChanged("\(endpoint) → HTTP \(status)")
        }
    }

    private func load(_ req: URLRequest) async throws -> (Data, Int) {
        var req = req
        let isAlexa = req.url!.host!.hasPrefix("alexa.")
        req.setValue(isAlexa ? Amazon.browserUserAgent : Amazon.appUserAgent, forHTTPHeaderField: "User-Agent")
        req.setValue(locale, forHTTPHeaderField: "Accept-Language")
        if isAlexa, !cookies.isEmpty {
            req.setValue(cookies.map { "\($0)=\($1)" }.joined(separator: "; "), forHTTPHeaderField: "Cookie")
        }
        let data: Data, response: URLResponse
        do { (data, response) = try await http.data(for: req) } catch { throw AlexaError.network(error) }
        guard let response = response as? HTTPURLResponse else { return (data, 0) }
        if isAlexa {
            let headers = response.allHeaderFields.reduce(into: [String: String]()) { $0["\($1.key)"] = "\($1.value)" }
            for cookie in HTTPCookie.cookies(withResponseHeaderFields: headers, for: response.url ?? base) {
                cookies[cookie.name] = cookie.value
            }
        }
        return (data, response.statusCode)
    }

    private func csrf() async throws -> String? {
        if let auth { return try await auth.value }
        let task = Task { try await authenticate() }
        auth = task
        do { return try await task.value } catch { auth = nil; throw error }
    }

    /// Refresh token → Amazon auth cookies for this domain → Alexa csrf cookie.
    private func authenticate() async throws -> String? {
        let form: [(String, String)] = [
            ("app_name", Amazon.appName), ("app_version", Amazon.appVersion), ("di.sdk.version", "6.12.4"),
            ("source_token", refreshToken), ("package_name", "com.amazon.echo"), ("di.hw.version", "iPhone"),
            ("platform", "iOS"), ("requested_token_type", "auth_cookies"), ("source_token_type", "refresh_token"),
            ("di.os.name", "iOS"), ("di.os.version", Amazon.osVersion), ("current_version", "6.12.4"),
            ("previous_version", "6.12.4"), ("domain", "www.\(domain)"),
        ]
        var req = URLRequest(url: URL(string: "https://api.amazon.com/auth/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let unreserved = CharacterSet.alphanumerics.union(.init(charactersIn: "-._~"))
        req.httpBody = Data(form.map { "\($0)=\($1.addingPercentEncoding(withAllowedCharacters: unreserved)!)" }
            .joined(separator: "&").utf8)
        let (data, status) = try await load(req)
        log.info("auth/token → \(status)")
        guard status == 200 else {
            throw (400..<500).contains(status) ? AlexaError.sessionExpired : AlexaError.endpointChanged("auth/token → HTTP \(status)")
        }
        let json = try? JSONSerialization.jsonObject(with: data)
        guard let byDomain = dig(json, "response", "tokens", "cookies") as? [String: [[String: Any]]] else {
            throw AlexaError.endpointChanged("auth/token: no cookies")
        }
        cookies = [:]
        for list in byDomain.values {
            for c in list {
                if let name = c["Name"] as? String, let value = c["Value"] as? String {
                    cookies[name] = value.replacingOccurrences(of: "\"", with: "")
                }
            }
        }
        // Alexa sets the csrf cookie on the first of these pages that answers (alexa-cookie2's list).
        for path in ["/api/language", "/spa/index.html", "/api/devices-v2/device?cached=false",
                     "/templates/oobe/d-device-pick.handlebars", "/api/strings"] {
            var page = URLRequest(url: URL(string: path, relativeTo: base)!)
            page.setValue(base.absoluteString + "/spa/index.html", forHTTPHeaderField: "Referer")
            page.setValue(base.absoluteString, forHTTPHeaderField: "Origin")
            _ = try await load(page)
            if let csrf = cookies["csrf"] { return csrf }
        }
        log.error("no csrf cookie from \(self.base.host ?? "", privacy: .public)")
        return nil  // reads still work; writes will 401/403 and surface as session expired
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: data) } catch {
            throw AlexaError.endpointChanged("unexpected JSON for \(T.self)")
        }
    }
}

// MARK: - DTOs (every field optional so a renamed field degrades instead of failing the whole decode)

struct DevicesDTO: Decodable {
    let devices: [DeviceDTO]?
}

struct DeviceDTO: Decodable {
    let serialNumber, accountName, deviceType: String?
    let online: Bool?
    let capabilities: [String]?

    var echoDevice: EchoDevice? {
        guard let serialNumber, let deviceType, capabilities?.contains("TIMERS_AND_ALARMS") == true else { return nil }
        return EchoDevice(id: serialNumber, name: accountName ?? serialNumber, deviceType: deviceType, isOnline: online ?? false)
    }
}

struct NotificationsDTO: Decodable {
    let notifications: [NotificationDTO]?

    func alerts(now: Date) -> [Alert] {
        (notifications ?? []).compactMap { $0.alert(now: now) }
            .sorted { ($0.fireDate ?? .distantFuture) < ($1.fireDate ?? .distantFuture) }
    }
}

/// Decodes to "present" whatever the JSON value is.
struct Present: Decodable { init(from decoder: Decoder) {} }

struct NotificationDTO: Decodable {
    let id, type, status, deviceSerialNumber, originalDate, originalTime: String?
    let timerLabel, alarmLabel, reminderLabel, recurringPattern: String?
    let triggerTime, alarmTime, remainingTime: Double?  // milliseconds
    let rRuleData: Present?

    /// Next occurrence per aioamazondevices' notification.py: timers use triggerTime, reminders alarmTime,
    /// alarms originalDate + originalTime in local time.
    func alert(now: Date) -> Alert? {
        guard let id, let deviceSerialNumber, status == "ON" else { return nil }
        let kind: AlertKind, label: String?
        switch type {
        case "Timer": (kind, label) = (.timer, timerLabel)
        case "Alarm", "MusicAlarm": (kind, label) = (.alarm, alarmLabel)
        case "Reminder": (kind, label) = (.reminder, reminderLabel)
        default: return nil
        }
        let repeats = recurringPattern?.isEmpty == false || rRuleData != nil
        var fire: Date?
        if kind == .timer {
            fire = triggerTime.map { Date(timeIntervalSince1970: $0 / 1000) } ?? remainingTime.map { now + $0 / 1000 }
        } else if kind == .reminder, let alarmTime {
            fire = Date(timeIntervalSince1970: alarmTime / 1000)
        } else if let originalTime {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            let time = String(originalTime.prefix(8))
            if repeats {
                // ponytail: next time-of-day only; weekday rules (RRULE) are ignored, so the row shows time + "repeats".
                let day = DateFormatter()
                day.locale = Locale(identifier: "en_US_POSIX")
                day.dateFormat = "yyyy-MM-dd"
                fire = f.date(from: "\(day.string(from: now)) \(time)").map { $0 > now ? $0 : $0 + 86400 }
            } else if let originalDate {
                fire = f.date(from: "\(originalDate) \(time)")
            }
        }
        if !repeats, let fire, fire < now - 60 { return nil }  // already fired
        return Alert(id: id, kind: kind, deviceID: deviceSerialNumber, fireDate: fire,
                     label: label?.isEmpty == false ? label : nil, repeats: repeats)
    }
}
