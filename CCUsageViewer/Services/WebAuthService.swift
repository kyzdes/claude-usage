import Foundation
import AppKit
import WebKit

@MainActor
final class WebAuthService: NSObject, ObservableObject {
    @Published var isAuthenticating = false
    @Published var authError: String?
    @Published var isAuthenticated = false

    private let storage: SessionKeyStorageProtocol
    private let apiService: ClaudeAPIServiceProtocol
    private var loginWindow: NSWindow?
    private var popupWindow: NSWindow?
    private var webView: WKWebView?
    private var cookieStore: WKHTTPCookieStore?
    private var isPolling = false
    private var alreadyCaptured = false

    init(
        storage: SessionKeyStorageProtocol = SessionKeyStorage(),
        apiService: ClaudeAPIServiceProtocol = ClaudeAPIService()
    ) {
        self.storage = storage
        self.apiService = apiService
        super.init()
        self.isAuthenticated = hasCredentials
    }

    func startLogin() {
        closeLoginWindow()

        isAuthenticating = true
        authError = nil
        alreadyCaptured = false

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Safari/605.1.15"
        wv.uiDelegate = self
        wv.navigationDelegate = self
        self.webView = wv
        self.cookieStore = config.websiteDataStore.httpCookieStore

        // Build content: hint banner + webview
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 740))
        container.wantsLayer = true

        let banner = NSView(frame: NSRect(x: 0, y: 700, width: 1000, height: 40))
        banner.wantsLayer = true
        banner.layer?.backgroundColor = NSColor(red: 0.15, green: 0.15, blue: 0.17, alpha: 1).cgColor

        let label = NSTextField(labelWithString: "Log in to your Claude account. The window will close automatically.")
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        banner.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: banner.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: banner.centerYAnchor)
        ])

        banner.autoresizingMask = [.width, .minYMargin]
        wv.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        wv.autoresizingMask = [.width, .height]

        container.addSubview(wv)
        container.addSubview(banner)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 740),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Log in to Claude"
        window.contentView = container
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.loginWindow = window

        // Only clear the sessionKey cookie (keep Google OAuth cookies intact)
        // Polling starts AFTER login page loads (see didFinish delegate)
        isPolling = false
        Task {
            let allCookies = await config.websiteDataStore.httpCookieStore.allCookies()
            for cookie in allCookies where cookie.name == "sessionKey" && cookie.domain.contains("claude.ai") {
                await config.websiteDataStore.httpCookieStore.deleteCookie(cookie)
            }
            wv.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
        }
    }

    func logout() {
        try? storage.deleteSessionKey()
        storage.deleteOrganizationId()
        isAuthenticated = false

        // Only clear sessionKey cookie, keep Google/auth cookies for smooth re-login
        Task {
            let dataStore = WKWebsiteDataStore.default()
            let cookies = await dataStore.httpCookieStore.allCookies()
            for cookie in cookies where cookie.name == "sessionKey" && cookie.domain.contains("claude.ai") {
                await dataStore.httpCookieStore.deleteCookie(cookie)
            }
        }
    }

    var hasCredentials: Bool {
        storage.getSessionKey() != nil && storage.getOrganizationId() != nil
    }

    // MARK: - Polling (DispatchQueue-based)

    private func scheduleNextPoll(webView: WKWebView, cookieStore: WKHTTPCookieStore?) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self, self.isPolling, !self.alreadyCaptured else { return }
            self.pollForLogin(webView: webView, cookieStore: cookieStore)
            if self.isPolling && !self.alreadyCaptured {
                self.scheduleNextPoll(webView: webView, cookieStore: cookieStore)
            }
        }
    }

    private func pollForLogin(webView: WKWebView, cookieStore: WKHTTPCookieStore?) {
        guard !alreadyCaptured else {
            isPolling = false
            return
        }

        guard let url = webView.url,
              let host = url.host,
              host.contains("claude.ai"),
              !url.path.contains("login") else {
            return // Not on logged-in page yet
        }

        // User is on claude.ai and NOT on /login — they logged in!
        // Only check cookie store — no JS injection (JS causes page flicker)
        guard let cookieStore else { return }
        Task {
            let cookies = await cookieStore.allCookies()
            if let sk = cookies.first(where: { $0.name == "sessionKey" && $0.domain.contains("claude.ai") }) {
                self.alreadyCaptured = true
                self.isPolling = false
                await self.handleCapturedSessionKey(sk.value)
            }
            // If no cookie yet, next poll tick will retry
        }
    }

    // MARK: - Session handling

    private func handleCapturedSessionKey(_ sessionKey: String) async {
        do {
            let orgs = try await apiService.fetchOrganizations(sessionKey: sessionKey)
            guard let orgId = orgs.first?.organizationId else {
                authError = "No organization found."
                isAuthenticating = false
                return
            }

            try storage.setSessionKey(sessionKey)
            storage.setOrganizationId(orgId)

            isAuthenticated = true
            isAuthenticating = false
            authError = nil
            closeLoginWindow()
        } catch {
            authError = "API validation failed: \(error.localizedDescription)"
            isAuthenticating = false
        }
    }

    private func closeLoginWindow() {
        isPolling = false
        let window = loginWindow
        loginWindow = nil
        webView = nil
        cookieStore = nil
        popupWindow?.close()
        popupWindow = nil
        if let window {
            DispatchQueue.main.async {
                window.orderOut(nil)
                window.close()
            }
        }
    }
}

// MARK: - NSWindowDelegate

extension WebAuthService: NSWindowDelegate {
    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isPolling = false
            if !self.isAuthenticated {
                self.isAuthenticating = false
            }
        }
    }
}

// MARK: - WKUIDelegate

extension WebAuthService: WKUIDelegate {
    /// Google OAuth opens a popup for accounts.google.com.
    /// We must create a real child WebView so window.opener.postMessage() works.
    @MainActor
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        let popupWebView = WKWebView(frame: .zero, configuration: configuration)
        popupWebView.customUserAgent = webView.customUserAgent
        popupWebView.uiDelegate = self

        let popup = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        popup.title = "Sign in with Google"
        popup.contentView = popupWebView
        popup.isReleasedWhenClosed = false
        popup.center()
        popup.makeKeyAndOrderFront(nil)
        self.popupWindow = popup

        return popupWebView
    }

    /// Called when the popup calls window.close() after OAuth completes
    @MainActor
    func webViewDidClose(_ webView: WKWebView) {
        popupWindow?.close()
        popupWindow = nil
    }
}

// MARK: - WKNavigationDelegate

extension WebAuthService: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            guard let self, !self.isPolling, !self.alreadyCaptured else { return }
            // Login page loaded — now start polling for when user completes login
            self.isPolling = true
            self.scheduleNextPoll(webView: webView, cookieStore: self.cookieStore)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        Task { @MainActor [weak self] in
            self?.authError = error.localizedDescription
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        Task { @MainActor [weak self] in
            self?.authError = error.localizedDescription
        }
    }
}
