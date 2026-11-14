import AppKit
import Combine
import Foundation
import Network
import SwiftUI
import WebKit

struct BrowserItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var url: String
    var date = Date()
}

struct DownloadItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var path: String
    var progress: Double
    var isComplete: Bool
    var error: String?
    var bytesWritten: Int64 = 0
    var expectedBytes: Int64 = 0
}

@MainActor
final class BrowserTab: ObservableObject, Identifiable {
    let id = UUID()
    let webView: WKWebView
    private var webViewObservations: [NSKeyValueObservation] = []
    @Published var title = "Новая вкладка"
    @Published var address = ""
    @Published var isLoading = false
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isHome = true
    @Published var isAbout = false
    @Published var isOffline = false
    @Published var favicon: NSImage?
    @Published var loadError: String?

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.isElementFullscreenEnabled = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webViewObservations = [
            webView.observe(\.title, options: [.new]) { [weak self] view, _ in
                DispatchQueue.main.async {
                    guard let self, let title = view.title, !title.isEmpty else { return }
                    self.title = title
                }
            },
            webView.observe(\.url, options: [.new]) { [weak self] view, _ in
                DispatchQueue.main.async {
                    guard let self, let url = view.url, !self.isHome, !self.isAbout, !self.isOffline else { return }
                    self.address = url.absoluteString
                }
            },
            webView.observe(\.isLoading, options: [.new]) { [weak self] view, _ in
                DispatchQueue.main.async { self?.isLoading = view.isLoading }
            },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] view, _ in
                DispatchQueue.main.async { self?.canGoBack = view.canGoBack }
            },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] view, _ in
                DispatchQueue.main.async { self?.canGoForward = view.canGoForward }
            }
        ]
    }

    func syncNavigationState() {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        isLoading = webView.isLoading
        if let pageTitle = webView.title, !pageTitle.isEmpty {
            title = pageTitle
        }
        if let url = webView.url, !isAbout && !isOffline && !isHome {
            address = url.absoluteString
        }
    }
}

@MainActor
final class BrowserStore: ObservableObject {
    static weak var active: BrowserStore?

    @Published var tabs: [BrowserTab] = []
    @Published var selectedTabID: UUID?
    @Published var bookmarks: [BrowserItem] = []
    @Published var history: [BrowserItem] = []
    @Published var downloads: [DownloadItem] = []

    private var tabSubscriptions: [UUID: AnyCancellable] = [:]
    private let defaults = UserDefaults.standard
    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.delta.browser.network")
    private var networkIsAvailable = true
    private var recentlyClosedURLs: [String] = []

    var selectedTab: BrowserTab? {
        tabs.first { $0.id == selectedTabID }
    }

    init() {
        bookmarks = decode([BrowserItem].self, key: "delta.bookmarks") ?? [
            BrowserItem(title: "Google", url: "https://www.google.com"),
            BrowserItem(title: "YouTube", url: "https://www.youtube.com"),
            BrowserItem(title: "Wikipedia", url: "https://www.wikipedia.org"),
            BrowserItem(title: "GitHub", url: "https://github.com"),
            BrowserItem(title: "Roblox", url: "https://www.roblox.com")
        ]
        history = decode([BrowserItem].self, key: "delta.history") ?? []
        downloads = decode([DownloadItem].self, key: "delta.downloads") ?? []
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.networkIsAvailable = path.status == .satisfied }
        }
        pathMonitor.start(queue: monitorQueue)

        let startupMode = defaults.string(forKey: "delta.startupMode") ?? "restore"
        let savedTabs = startupMode == "restore" ? (defaults.stringArray(forKey: "delta.openTabs") ?? []) : []
        if !savedTabs.isEmpty {
            for url in savedTabs.prefix(20) {
                if url == "about" {
                    let tab = BrowserTab()
                    register(tab)
                    showAbout(in: tab)
                } else if url == "delta://home" {
                    let tab = BrowserTab()
                    register(tab)
                } else {
                    newTab(initialAddress: url)
                }
            }
        } else {
            newTab()
            if startupMode == "homepage" {
                navigate(defaults.string(forKey: "delta.homepage") ?? "https://www.google.com")
            }
        }
    }

    func newTab(initialAddress: String? = nil) {
        let tab = BrowserTab()
        register(tab)
        if let initialAddress {
            navigate(initialAddress, in: tab)
        } else if defaults.string(forKey: "delta.newTabMode") == "about" {
            showAbout(in: tab)
        }
        persistOpenTabs()
    }

    func closeTab(_ tab: BrowserTab) {
        if !tab.address.isEmpty && !tab.isHome && !tab.isAbout && !tab.isOffline {
            recentlyClosedURLs.append(tab.address)
            recentlyClosedURLs = Array(recentlyClosedURLs.suffix(10))
        }
        tab.webView.stopLoading()
        tabSubscriptions[tab.id] = nil
        tabs.removeAll { $0.id == tab.id }
        if tabs.isEmpty {
            newTab()
        } else if selectedTabID == tab.id {
            selectedTabID = tabs.last?.id
        }
        persistOpenTabs()
    }

    func reopenClosedTab() {
        guard let url = recentlyClosedURLs.popLast() else { return }
        newTab(initialAddress: url)
    }

    func selectTab(_ tab: BrowserTab) {
        selectedTabID = tab.id
    }

    func navigate(_ input: String, in tab: BrowserTab? = nil) {
        guard let tab = tab ?? selectedTab else { return }
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if text.caseInsensitiveCompare("about") == .orderedSame ||
            text.caseInsensitiveCompare("about:blank") == .orderedSame {
            showAbout(in: tab)
            return
        }

        let destination: URL?
        if let parsed = URL(string: text), let scheme = parsed.scheme?.lowercased(),
           ["http", "https"].contains(scheme), parsed.host != nil {
            destination = parsed
        } else if !text.contains(where: \.isWhitespace),
                  text.contains("."),
                  let parsed = URL(string: "https://" + text),
                  parsed.host != nil {
            destination = parsed
        } else {
            let query = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
            let engine = defaults.string(forKey: "delta.searchEngine") ?? "Google"
            let base: String
            switch engine {
            case "DuckDuckGo": base = "https://duckduckgo.com/?q="
            case "Bing": base = "https://www.bing.com/search?q="
            default: base = "https://www.google.com/search?q="
            }
            destination = URL(string: base + query)
        }

        guard let destination else { return }
        tab.isHome = false
        tab.isAbout = false
        tab.isOffline = false
        tab.loadError = nil
        tab.title = "Загрузка…"
        tab.address = destination.absoluteString
        tab.webView.load(URLRequest(url: destination, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 120))
        persistOpenTabs()
    }

    func showHome(in tab: BrowserTab? = nil) {
        navigate(defaults.string(forKey: "delta.homepage") ?? "https://www.google.com", in: tab)
    }

    func showAbout(in tab: BrowserTab) {
        tab.webView.stopLoading()
        tab.title = "about"
        tab.address = "about"
        tab.isHome = false
        tab.isAbout = true
        tab.isOffline = false
        tab.loadError = nil
        persistOpenTabs()
    }

    func showOffline(in tab: BrowserTab) {
        tab.title = "Нет подключения к интернету"
        tab.address = ""
        tab.isHome = false
        tab.isAbout = false
        tab.isOffline = true
        tab.loadError = nil
    }

    func handleNavigationFailure(_ error: Error, in tab: BrowserTab) {
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled else { return }
        tab.loadError = error.localizedDescription
        let networkErrors = [
            NSURLErrorNotConnectedToInternet,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorCannotFindHost,
            NSURLErrorCannotConnectToHost,
            NSURLErrorDNSLookupFailed,
            NSURLErrorTimedOut
        ]
        guard nsError.domain == NSURLErrorDomain, networkErrors.contains(nsError.code) else { return }
        guard networkIsAvailable else {
            showOffline(in: tab)
            return
        }

        let failedAddress = tab.address
        let probes = [
            URL(string: "https://www.apple.com/library/test/success.html")!,
            URL(string: "https://www.cloudflare.com/cdn-cgi/trace")!
        ]
        Task { @MainActor in
            let results = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
                for url in probes {
                    group.addTask {
                        do {
                            let request = URLRequest(url: url, timeoutInterval: 4)
                            let (_, response) = try await URLSession.shared.data(for: request)
                            return (response as? HTTPURLResponse) != nil
                        } catch let error as URLError {
                            NSLog("Delta connectivity probe failed: %@", error.localizedDescription)
                            return false
                        } catch {
                            NSLog("Delta connectivity probe encountered an unexpected error: %@", error.localizedDescription)
                            return true
                        }
                    }
                }
                var results: [Bool] = []
                for await result in group { results.append(result) }
                return results
            }
            if results.allSatisfy({ !$0 }), tab.address == failedAddress {
                showOffline(in: tab)
            }
        }
    }

    func recordVisit(_ tab: BrowserTab) {
        guard !tab.address.isEmpty, !tab.isHome, !tab.isAbout, !tab.isOffline else { return }
        let item = BrowserItem(title: tab.title, url: tab.address)
        history.insert(item, at: 0)
        history = Array(history.prefix(1000))
        persist(history, key: "delta.history")
    }

    func addBookmark(url: String, title: String) {
        guard !url.isEmpty, !bookmarks.contains(where: { $0.url == url }) else { return }
        bookmarks.insert(BrowserItem(title: title, url: url), at: 0)
        persist(bookmarks, key: "delta.bookmarks")
    }

    func removeBookmark(_ item: BrowserItem) {
        bookmarks.removeAll { $0.id == item.id }
        persist(bookmarks, key: "delta.bookmarks")
    }

    func clearHistory() {
        history.removeAll()
        persist(history, key: "delta.history")
    }

    func clearWebsiteData() {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast) {}
    }

    func persistOpenTabs() {
        let urls = tabs.compactMap { tab -> String? in
            guard !tab.isOffline else { return nil }
            if tab.isAbout { return "about" }
            if tab.isHome { return "delta://home" }
            guard !tab.address.isEmpty else { return nil }
            return tab.address
        }
        defaults.set(urls, forKey: "delta.openTabs")
    }

    func updateDownload(_ item: DownloadItem) {
        if let index = downloads.firstIndex(where: { $0.id == item.id }) {
            downloads[index] = item
        } else {
            downloads.insert(item, at: 0)
        }
        persist(downloads, key: "delta.downloads")
    }

    func openDownloadsFolder() {
        let path = defaults.string(forKey: "delta.downloadFolder") ?? NSHomeDirectory() + "/Downloads"
        NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true))
    }

    func openDownload(_ item: DownloadItem) {
        NSWorkspace.shared.open(URL(fileURLWithPath: item.path))
    }

    private func persist<T: Encodable>(_ value: T, key: String) {
        do {
            defaults.set(try JSONEncoder().encode(value), forKey: key)
        } catch {
            NSLog("Delta could not save %@: %@", key, error.localizedDescription)
        }
    }

    private func register(_ tab: BrowserTab) {
        tabs.append(tab)
        selectedTabID = tab.id
        tabSubscriptions[tab.id] = tab.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.objectWillChange.send() }
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            NSLog("Delta could not load %@: %@", key, error.localizedDescription)
            return nil
        }
    }
}

@MainActor
final class BrowserWebCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    weak var store: BrowserStore?
    weak var tab: BrowserTab?
    private var activeDownloads: [ObjectIdentifier: DownloadItem] = [:]

    init(store: BrowserStore, tab: BrowserTab) {
        self.store = store
        self.tab = tab
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        tab?.syncNavigationState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let tab else { return }
        tab.syncNavigationState()
        if let pageTitle = webView.title, !pageTitle.isEmpty {
            tab.title = pageTitle
        } else {
            tab.title = webView.url?.host ?? "Страница"
        }
        tab.loadError = nil
        store?.recordVisit(tab)
        loadFavicon(for: tab)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        tab?.syncNavigationState()
        handle(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        tab?.syncNavigationState()
        handle(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard let tab else { return }
        tab.isLoading = false
        tab.loadError = "Внутренний процесс WebKit завершился. Попробуйте перезагрузить страницу."
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if navigationResponse.canShowMIMEType {
            decisionHandler(.allow)
        } else {
            decisionHandler(.download)
        }
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction,
                 didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil, let store else { return nil }
        store.newTab()
        guard let newTab = store.selectedTab else { return nil }
        newTab.webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        return newTab.webView
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        tab?.syncNavigationState()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(.allow)
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let defaults = UserDefaults.standard
        let folder = defaults.string(forKey: "delta.downloadFolder") ?? NSHomeDirectory() + "/Downloads"
        let directory = URL(fileURLWithPath: folder, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            store?.updateDownload(DownloadItem(
                name: suggestedFilename,
                path: directory.appendingPathComponent(suggestedFilename).path,
                progress: 0,
                isComplete: false,
                error: error.localizedDescription
            ))
            completionHandler(nil)
            return
        }
        let destination = uniqueURL(directory: directory, filename: suggestedFilename)
        let item = DownloadItem(name: suggestedFilename, path: destination.path, progress: 0, isComplete: false)
        activeDownloads[ObjectIdentifier(download)] = item
        store?.updateDownload(item)
        completionHandler(destination)
    }

    func download(_ download: WKDownload, didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                  totalBytesExpectedToWrite: Int64) {
        let key = ObjectIdentifier(download)
        guard var item = activeDownloads[key] else { return }
        item.progress = totalBytesExpectedToWrite > 0
            ? min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
            : 0
        item.bytesWritten = totalBytesWritten
        item.expectedBytes = totalBytesExpectedToWrite
        store?.updateDownload(item)
    }

    func downloadDidFinish(_ download: WKDownload) {
        let key = ObjectIdentifier(download)
        guard var item = activeDownloads.removeValue(forKey: key) else { return }
        item.progress = 1
        item.isComplete = true
        store?.updateDownload(item)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        let key = ObjectIdentifier(download)
        guard var item = activeDownloads.removeValue(forKey: key) else { return }
        item.error = error.localizedDescription
        store?.updateDownload(item)
    }

    private func handle(_ error: Error) {
        tab?.syncNavigationState()
        if let tab { store?.handleNavigationFailure(error, in: tab) }
    }

    private func uniqueURL(directory: URL, filename: String) -> URL {
        let base = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        let ext = URL(fileURLWithPath: filename).pathExtension
        var candidate = directory.appendingPathComponent(filename)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) (\(index))").appendingPathExtension(ext)
            index += 1
        }
        return candidate
    }

    private func loadFavicon(for tab: BrowserTab) {
        guard let host = tab.webView.url?.host else { return }
        let faviconURL = URL(string: "https://\(host)/favicon.ico")!
        URLSession.shared.dataTask(with: faviconURL) { data, _, _ in
            guard let data, let image = NSImage(data: data) else { return }
            Task { @MainActor in tab.favicon = image }
        }.resume()
    }
}
