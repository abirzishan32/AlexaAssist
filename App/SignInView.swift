import SwiftUI
import WebKit

/// Hosts Amazon's own sign-in page; the password and one-time code never touch our UI.
struct SignInView: View {
    @Environment(AppModel.self) private var model
    let onFinish: () -> Void
    @State private var request: SignInRequest?
    @State private var finishing = false
    @State private var failure: String?

    var body: some View {
        VStack(spacing: 0) {
            if let failure {
                HStack {
                    Text("Sign-in failed: \(failure)").foregroundStyle(.red).textSelection(.enabled)
                    Spacer()
                    Button("Try again") { start() }
                }
                .padding(10)
            }
            if finishing {
                ProgressView("Finishing sign-in…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let request {
                AmazonWebView(request: request) { handle($0, request) }.id(request.url)
            }
        }
        .frame(width: 480, height: 700)
        .onAppear(perform: start)
    }

    private func start() {
        failure = nil
        finishing = false
        request = SignInRequest()  // fresh PKCE + device serial every attempt
    }

    /// True when `url` is Amazon's post-login redirect, so the web view stops there.
    private func handle(_ url: URL, _ request: SignInRequest) -> Bool {
        guard let code = request.authorizationCode(from: url) else { return false }
        finishing = true
        Task {
            do {
                model.signedIn(try await AuthService.signIn(code: code, request: request))
                onFinish()
            } catch {
                failure = "\(error)"
                finishing = false
                self.request = nil
            }
        }
        return true
    }
}

struct AmazonWebView: NSViewRepresentable {
    let request: SignInRequest
    let onNavigate: (URL) -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(onNavigate: onNavigate) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()  // separate from Safari; nothing outlives the window
        let view = WKWebView(frame: .zero, configuration: config)
        view.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Safari/605.1.15"
        view.navigationDelegate = context.coordinator
        let store = config.websiteDataStore.httpCookieStore
        Task {
            for (name, value) in request.cookies {
                if let cookie = HTTPCookie(properties: [.domain: ".amazon.com", .path: "/", .name: name, .value: value, .secure: "TRUE"]) {
                    await store.setCookie(cookie)
                }
            }
            view.load(URLRequest(url: request.url))
        }
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.onNavigate = onNavigate
    }

    /// Watches every way the maplanding redirect can surface and reports it once.
    final class Coordinator: NSObject, WKNavigationDelegate {
        var onNavigate: (URL) -> Bool
        private var done = false

        init(onNavigate: @escaping (URL) -> Bool) { self.onNavigate = onNavigate }

        private func check(_ url: URL?) -> Bool {
            guard !done, let url, onNavigate(url) else { return false }
            done = true
            return true
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            done ? .cancel : check(action.request.url) ? .cancel : .allow
        }

        func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
            if check(webView.url) { webView.stopLoading() }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            _ = check((error as NSError).userInfo[NSURLErrorFailingURLErrorKey] as? URL)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            _ = check(webView.url)
        }
    }
}
