import Foundation
import AppKit
import WebKit
import os.log

private let logger = Logger(subsystem: "com.vkuznetsov.CCUsageViewer", category: "WebAuth")

@MainActor
final class WebAuthService: NSObject, ObservableObject {
    @Published var isAuthenticating = false
    @Published var authError: String?
    @Published var isAuthenticated = false

    private let storage: SessionKeyStorageProtocol
    private let apiService: ClaudeAPIServiceProtocol
    private var loginWindow: NSWindow?
    private var webView: WKWebView?
    private var cookieStore: WKHTTPCookieStore?
    private var pollingTask: Task<Void, Never>?
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
        // Debug: write to file immediately to confirm this is called
        let debugLine = "[\(Date())] startLogin TOP\n"
        try? debugLine.write(toFile: "/tmp/ccusage_auth.log", atomically: false, encoding: .utf8)

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

        let url = URL(string: "https://claude.ai/login")!
        wv.load(URLRequest(url: url))

        debugLog("startLogin() called — window opened, starting polling task")
        cookieStore?.add(self)
        pollingTask?.cancel()
        let pollingWebView = wv
        let pollingCookieStore = self.cookieStore
        pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }
                // Use strong refs to webView/cookieStore captured at creation
                self?.pollForLogin(webView: pollingWebView, cookieStore: pollingCookieStore)
            }
        }
    }

    func logout() {
        try? storage.deleteSessionKey()
        storage.deleteOrganizationId()
        isAuthenticated = false

        Task {
            let dataStore = WKWebsiteDataStore.default()
            let cookies = await dataStore.httpCookieStore.allCookies()
            for cookie in cookies where cookie.domain.contains("claude.ai") {
                await dataStore.httpCookieStore.deleteCookie(cookie)
            }
        }
    }

    var hasCredentials: Bool {
        storage.getSessionKey() != nil && storage.getOrganizationId() != nil
    }

    // MARK: - Polling (Timer-based, guaranteed to fire on main run loop)

    private func debugLog(_ msg: String) {
        let line = "[\(Date())] \(msg)\n"
        let path = "/tmp/ccusage_auth.log"
        if let fh = FileHandle(forWritingAtPath: path) {
            fh.seekToEndOfFile()
            fh.write(line.data(using: .utf8)!)
            fh.closeFile()
        } else {
            FileManager.default.createFile(atPath: path, contents: line.data(using: .utf8))
        }
    }

    private func pollForLogin(webView: WKWebView, cookieStore: WKHTTPCookieStore?) {
        debugLog("pollForLogin called. alreadyCaptured=\(alreadyCaptured), url=\(webView.url?.absoluteString ?? "nil")")

        guard !alreadyCaptured else {
            pollingTask?.cancel()
            return
        }

        guard let url = webView.url,
              let host = url.host,
              host.contains("claude.ai"),
              !url.path.contains("login") else {
            debugLog("pollForLogin: not on logged-in page yet")
            return
        }

        debugLog("pollForLogin: on logged-in page! Trying to capture cookies...")

        // We're on claude.ai and NOT on /login — user is logged in!
        Task {
            // Try cookie store first
            if let cookieStore {
                let cookies = await cookieStore.allCookies()
                let claudeCookies = cookies.filter { $0.domain.contains("claude.ai") }
                debugLog("pollForLogin: found \(claudeCookies.count) claude.ai cookies")
                if let sk = claudeCookies.first(where: { $0.name == "sessionKey" }) {
                    debugLog("pollForLogin: found sessionKey cookie!")
                    self.alreadyCaptured = true
                    self.pollingTask?.cancel()
                    await self.handleCapturedSessionKey(sk.value)
                    return
                }
            }

            // Fallback: call /api/organizations from page context via JS
            debugLog("pollForLogin: no sessionKey cookie, trying JS fallback...")
            let js = """
            (async () => {
                try {
                    const r = await fetch('/api/organizations', { credentials: 'include' });
                    const j = await r.json();
                    return JSON.stringify(j);
                } catch(e) {
                    return JSON.stringify({ error: e.message });
                }
            })()
            """
            do {
                let result = try await webView.evaluateJavaScript(js)
                if let jsonString = result as? String,
                   let data = jsonString.data(using: .utf8),
                   let orgs = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                   let firstOrg = orgs.first,
                   let orgId = firstOrg["uuid"] as? String ?? firstOrg["id"] as? String {
                    debugLog("pollForLogin: JS fallback got orgId=\(orgId)")
                    self.alreadyCaptured = true
                    self.pollingTask?.cancel()
                    await self.handleAuthenticatedSession(organizationId: orgId)
                } else {
                    debugLog("pollForLogin: JS fallback returned no valid orgs")
                }
            } catch {
                debugLog("pollForLogin: JS error: \(error)")
            }
        }
    }

    /// Called when we confirmed the session is authenticated via JS API call
    private func handleAuthenticatedSession(organizationId: String) async {
        // The WKWebView has a valid session. Extract the sessionKey cookie.
        // First try WKHTTPCookieStore
        if let cookieStore {
            let cookies = await cookieStore.allCookies()
            if let sk = cookies.first(where: { $0.name == "sessionKey" && $0.domain.contains("claude.ai") }) {
                try? storage.setSessionKey(sk.value)
                storage.setOrganizationId(organizationId)
                isAuthenticated = true
                isAuthenticating = false
                authError = nil
                closeLoginWindow()
                return
            }
        }

        // If cookie store doesn't give us sessionKey, use JS to make API call
        // and store orgId — we'll use WKWebView-based fetching as fallback
        // For now, try extracting from document.cookie (non-httpOnly cookies)
        if let webView {
            let cookieString = try? await webView.evaluateJavaScript("document.cookie") as? String
            if let cookieString {
                let pairs = cookieString.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
                for pair in pairs {
                    let parts = pair.split(separator: "=", maxSplits: 1)
                    if parts.count == 2 && parts[0] == "sessionKey" {
                        let value = String(parts[1])
                        try? storage.setSessionKey(value)
                        storage.setOrganizationId(organizationId)
                        isAuthenticated = true
                        isAuthenticating = false
                        authError = nil
                        closeLoginWindow()
                        return
                    }
                }
            }
        }

        // Last resort: we confirmed the user is logged in, save orgId
        // and mark as authenticated (the API service will use WKWebView cookies)
        storage.setOrganizationId(organizationId)
        // Store a placeholder — the actual requests will use the WKWebView's cookie store
        try? storage.setSessionKey("wkwebview-session-active")
        isAuthenticated = true
        isAuthenticating = false
        authError = nil
        closeLoginWindow()
    }

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
        pollingTask?.cancel()
        pollingTask = nil
        cookieStore?.remove(self)
        loginWindow?.close()
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            self?.loginWindow = nil
            self?.webView = nil
            self?.cookieStore = nil
        }
    }
}

// MARK: - WKHTTPCookieStoreObserver (instant cookie detection)

extension WebAuthService: WKHTTPCookieStoreObserver {
    nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        Task { @MainActor [weak self] in
            guard let self, !self.alreadyCaptured else { return }
            // Cookie changed — check if sessionKey appeared
            let cookies = await cookieStore.allCookies()
            if let sk = cookies.first(where: { $0.name == "sessionKey" && $0.domain.contains("claude.ai") }) {
                self.alreadyCaptured = true
                await self.handleCapturedSessionKey(sk.value)
            }
        }
    }
}

// MARK: - NSWindowDelegate

extension WebAuthService: NSWindowDelegate {
    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.pollingTask?.cancel()
            self.pollingTask = nil
            self.cookieStore?.remove(self)
            if !self.isAuthenticated {
                self.isAuthenticating = false
            }
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 500_000_000)
                self?.loginWindow = nil
                self?.webView = nil
                self?.cookieStore = nil
            }
        }
    }
}

// MARK: - WKUIDelegate

extension WebAuthService: WKUIDelegate {
    @MainActor
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil || navigationAction.targetFrame?.isMainFrame == false {
            webView.load(navigationAction.request)
        }
        return nil
    }
}

// MARK: - WKNavigationDelegate

extension WebAuthService: WKNavigationDelegate {
    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // didFinish triggers URL polling check on next cycle
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
