import CryptoKit
import Foundation
import OSLog
import Security

// Flow and constants follow aioamazondevices (login.py / http_wrapper.py / const/http.py) and alexa-cookie2.
enum Amazon {
    static let appVersion = "2.2.663733.0"
    static let osVersion = "18.5"
    static let softwareVersion = "35602678"
    static let deviceType = "A2IVLV5VM2W81"  // Alexa iOS app
    static let appName = "AlexaAssist"
    static let appUserAgent = "AmazonWebView/AmazonAlexa/\(appVersion)/iOS/\(osVersion)/iPhone"
    static let browserUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/152.0.0.0 Safari/537.36 Edg/152.0.0.0"
}

/// Everything needed to talk to Amazon again later; cookies are re-minted from the refresh token.
struct AmazonSession: Codable, Sendable {
    let refreshToken: String
    let domain: String      // "amazon.com", "amazon.de", …, detected after sign-in
    let customerID: String
}

/// One sign-in attempt: Amazon's OAuth page for the Alexa iOS app, with PKCE, registering this Mac as an app device.
struct SignInRequest: Sendable {
    let url: URL
    /// Set these on .amazon.com in the web view before loading `url` (they keep Amazon from showing a captcha in most cases).
    let cookies: [String: String]
    let serial: String
    let verifier: String
    var clientID: String { Data("\(serial)#\(Amazon.deviceType)".utf8).hex }

    init() {
        let serial = UUID().uuidString.replacingOccurrences(of: "-", with: "").uppercased()
        let verifier = Data((0..<32).map { _ in UInt8.random(in: 0...255) }).base64URL
        let mapMD = #"{"device_user_dictionary":[],"device_registration_data":{"software_version":"\#(Amazon.softwareVersion)"},"app_identifier":{"app_version":"\#(Amazon.appVersion)","bundle_id":"com.amazon.echo"}}"#
        var c = URLComponents(string: "https://www.amazon.com/ap/signin")!
        c.queryItems = [
            "openid.return_to": "https://www.amazon.com/ap/maplanding",
            "openid.oa2.code_challenge_method": "S256",
            "openid.assoc_handle": "amzn_dp_project_dee_ios",
            "openid.identity": "http://specs.openid.net/auth/2.0/identifier_select",
            "pageId": "amzn_dp_project_dee_ios",
            "accountStatusPolicy": "P1",
            "openid.claimed_id": "http://specs.openid.net/auth/2.0/identifier_select",
            "openid.mode": "checkid_setup",
            "openid.ns.oa2": "http://www.amazon.com/ap/ext/oauth/2",
            "openid.oa2.client_id": "device:" + Data("\(serial)#\(Amazon.deviceType)".utf8).hex,
            "language": "en-US",
            "openid.ns.pape": "http://specs.openid.net/extensions/pape/1.0",
            "openid.oa2.code_challenge": Data(SHA256.hash(data: Data(verifier.utf8))).base64URL,
            "openid.oa2.scope": "device_auth_access",
            "openid.ns": "http://specs.openid.net/auth/2.0",
            "openid.pape.max_auth_age": "0",
            "openid.oa2.response_type": "code",
        ].map(URLQueryItem.init)
        self.serial = serial
        self.verifier = verifier
        url = c.url!
        cookies = [
            "frc": Data((0..<313).map { _ in UInt8.random(in: 0...255) }).base64EncodedString().trimmingCharacters(in: ["="]),
            "map-md": Data(mapMD.utf8).base64EncodedString().trimmingCharacters(in: ["="]),
            "amzn-app-id": "MAPiOSLib/6.0/ToHideRetailLink",
        ]
    }

    /// Amazon redirects to /ap/maplanding with the code once sign-in (including the one-time code) succeeds.
    func authorizationCode(from url: URL) -> String? {
        guard url.path.hasSuffix("/ap/maplanding") else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "openid.oa2.authorization_code" }?.value
    }
}

enum AuthService {
    private static let log = Logger(subsystem: "dev.alexaassist", category: "auth")

    /// Authorization code → registered device → detected Amazon site → account customer ID.
    static func signIn(code: String, request: SignInRequest) async throws -> AmazonSession {
        let (refreshToken, homeRegion) = try await register(code: code, request: request)
        let domain = homeRegion == "FE"
            ? "amazon.co.jp"
            : try await CloudBackend(refreshToken: refreshToken, domain: "amazon.com", customerID: "").alexaDomain()
        log.info("account domain: \(domain, privacy: .public)")
        let customerID = try await CloudBackend(refreshToken: refreshToken, domain: domain, customerID: "").accountCustomerID()
        return AmazonSession(refreshToken: refreshToken, domain: domain, customerID: customerID)
    }

    private static func register(code: String, request: SignInRequest) async throws -> (token: String, homeRegion: String?) {
        let body: [String: Any] = [
            "requested_extensions": ["device_info", "customer_info"],
            "cookies": ["website_cookies": [], "domain": ".amazon.com"],
            "registration_data": [
                "domain": "Device", "app_version": Amazon.appVersion, "device_type": Amazon.deviceType,
                "device_name": "%FIRST_NAME%'s%DUPE_STRATEGY_1ST%\(Amazon.appName)",
                "os_version": Amazon.osVersion, "device_serial": request.serial, "device_model": "iPhone",
                "app_name": Amazon.appName, "software_version": Amazon.softwareVersion,
            ],
            "auth_data": [
                "use_global_authentication": "true",
                "client_id": request.clientID, "authorization_code": code, "code_verifier": request.verifier,
                "code_algorithm": "SHA-256", "client_domain": "DeviceLegacy",
            ],
            "user_context_map": ["frc": request.cookies["frc"]!],
            "requested_token_type": ["bearer", "mac_dms", "website_cookies", "store_authentication_cookie"],
        ]
        var req = URLRequest(url: URL(string: "https://api.amazon.com/auth/register")!)
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(Amazon.appUserAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("api.amazon.com", forHTTPHeaderField: "x-amzn-identity-auth-domain")
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await URLSession(configuration: .ephemeral).data(for: req) } catch { throw AlexaError.network(error) }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        log.info("auth/register → \(status)")
        let json = try? JSONSerialization.jsonObject(with: data)
        guard let token = dig(json, "response", "success", "tokens", "bearer", "refresh_token") as? String else {
            let message = dig(json, "response", "error", "message") as? String ?? "HTTP \(status)"
            throw AlexaError.endpointChanged("device registration: \(message)")
        }
        return (token, dig(json, "response", "success", "extensions", "customer_info", "home_region") as? String)
    }
}

/// The session lives in one Keychain generic-password item.
enum CredentialStore {
    private static var query: [CFString: Any] { [
        kSecClass: kSecClassGenericPassword,
        kSecAttrService: "dev.alexaassist.amazon",
        kSecAttrAccount: "session",
    ] }

    static func save(_ session: AmazonSession) throws {
        delete()
        var item = query
        item[kSecValueData] = try JSONEncoder().encode(session)
        item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }

    static func load() -> AmazonSession? {
        var q = query
        q[kSecReturnData] = true
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(AmazonSession.self, from: data)
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}

func dig(_ json: Any?, _ path: String...) -> Any? {
    path.reduce(json) { ($0 as? [String: Any])?[$1] }
}

extension Data {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
