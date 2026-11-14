import AppKit
import SwiftUI
import WebKit

@main
struct DeltaApp: App {
    @NSApplicationDelegateAdaptor(DeltaApplicationDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Delta", id: "main") {
            BrowserWindow()
                .frame(minWidth: 820, minHeight: 560)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Новая вкладка") { BrowserStore.active?.newTab() }
                    .keyboardShortcut("t", modifiers: .command)
                Button("Новое окно") { NotificationCenter.default.post(name: .deltaNewWindow, object: nil) }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .newItem) {
                Button("Закрыть вкладку") {
                    if let tab = BrowserStore.active?.selectedTab { BrowserStore.active?.closeTab(tab) }
                }
                    .keyboardShortcut("w", modifiers: .command)
                Button("Повторно открыть закрытую вкладку") {
                    BrowserStore.active?.reopenClosedTab()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            }
            CommandGroup(after: .appInfo) {
                Button("Проверить обновления Delta…") {
                    NotificationCenter.default.post(name: .deltaCheckUpdates, object: nil)
                }
            }
        }

        Window("Настройки Delta", id: "settings") {
            SettingsView()
                .frame(minWidth: 520, minHeight: 520)
        }
    }
}

final class DeltaApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let icon = NSImage(contentsOf: iconURL) else {
            NSLog("Delta app icon could not be loaded from the app bundle.")
            return
        }
        NSApp.applicationIconImage = icon
    }
}

extension Notification.Name {
    static let deltaNewWindow = Notification.Name("delta.newWindow")
    static let deltaClearHistory = Notification.Name("delta.clearHistory")
    static let deltaCheckUpdates = Notification.Name("delta.checkUpdates")
}

struct BrowserWindow: View {
    @StateObject private var store = BrowserStore()
    @State private var addressText = ""
    @State private var panel: BrowserPanel?
    @FocusState private var addressFocused: Bool
    @AppStorage("delta.theme") private var theme = "Системная"
    @AppStorage("delta.zoom") private var zoom = 1.0
    @ObservedObject private var updateManager = UpdateManager.shared
    @State private var showingUpdateNotice = false
    @State private var updateAlertTitle = "Обновление Delta"
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            tabStrip
            navigationBar
            Divider()
            pageContent
        }
        .scaleEffect(zoom, anchor: .topLeading)
        .preferredColorScheme(theme == "Светлая" ? .light : (theme == "Тёмная" ? .dark : nil))
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: store.selectedTabID) { _ in
            BrowserStore.active = store
            addressText = store.selectedTab?.address ?? ""
        }
        .onChange(of: store.selectedTab?.address) { newAddress in
            addressText = newAddress ?? ""
        }
        .onReceive(NotificationCenter.default.publisher(for: .deltaNewWindow)) { _ in
            if BrowserStore.active === store { newWindow() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .deltaClearHistory)) { _ in store.clearHistory() }
        .onReceive(NotificationCenter.default.publisher(for: .deltaCheckUpdates)) { _ in
            Task {
                await updateManager.checkForUpdates(showStatus: true)
                if updateManager.availableVersion == nil {
                    if case .failed = updateManager.state {
                        updateAlertTitle = "Не удалось проверить обновления"
                    } else {
                        updateAlertTitle = "Проверка обновлений"
                    }
                    showingUpdateNotice = true
                }
            }
        }
        .onAppear {
            BrowserStore.active = store
            addressText = store.selectedTab?.address ?? ""
            Task { await updateManager.checkForUpdates() }
        }
        .onChange(of: updateManager.updateStatus) { _ in
            if case .failed = updateManager.state {
                updateAlertTitle = "Не удалось обновить Delta"
                showingUpdateNotice = true
            }
        }
        .alert(updateAlertTitle, isPresented: $showingUpdateNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(updateManager.updateStatus)
        }
        .background(WindowActivationObserver(store: store))
        .sheet(item: $panel) { panel in
            BrowserPanelView(panel: panel, store: store)
                .frame(minWidth: 440, minHeight: 400)
        }
    }

    private var tabStrip: some View {
        HStack(spacing: 5) {
            ForEach(store.tabs) { tab in
                HStack(spacing: 7) {
                    if let image = tab.favicon {
                        Image(nsImage: image).resizable().frame(width: 14, height: 14)
                    } else {
                        Image(systemName: tab.isHome ? "sparkle" : "globe")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Text(tab.title).lineLimit(1).font(.system(size: 12))
                    Button { store.closeTab(tab) } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .opacity(store.selectedTabID == tab.id ? 0.8 : 0.55)
                }
                .padding(.horizontal, 10)
                .frame(width: 190, height: 34)
                .background(store.selectedTabID == tab.id ? Color(nsColor: .controlBackgroundColor) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .contentShape(Rectangle())
                .onTapGesture { store.selectTab(tab) }
                .contextMenu {
                    Button("Закрыть вкладку") { store.closeTab(tab) }
                    Button("Добавить в закладки") {
                        store.addBookmark(url: tab.address, title: tab.title)
                    }
                }
            }
            Button { store.newTab() } label: {
                Image(systemName: "plus").font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .help("Новая вкладка (⌘T)")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var navigationBar: some View {
        HStack(spacing: 8) {
            navButton("chevron.left", help: "Назад", enabled: store.selectedTab?.canGoBack ?? false) {
                store.selectedTab?.webView.goBack()
            }
            navButton("chevron.right", help: "Вперёд", enabled: store.selectedTab?.canGoForward ?? false) {
                store.selectedTab?.webView.goForward()
            }
            navButton(store.selectedTab?.isLoading == true ? "xmark" : "arrow.clockwise",
                      help: store.selectedTab?.isLoading == true ? "Остановить" : "Обновить") {
                if let tab = store.selectedTab, tab.isLoading { tab.webView.stopLoading() }
                else { store.selectedTab?.webView.reload() }
            }
            TextField("Введите адрес или поисковый запрос", text: $addressText)
                .textFieldStyle(.plain)
                .padding(.horizontal, 13)
                .frame(height: 34)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .focused($addressFocused)
                .onSubmit { store.navigate(addressText); addressFocused = false }
                .onChange(of: addressFocused) { focused in
                    guard focused else { return }
                    DispatchQueue.main.async {
                        (NSApp.keyWindow?.firstResponder as? NSTextView)?.selectAll(nil)
                    }
                }
            navButton("house", help: "Домой") { store.showHome() }
            navButton("star", help: "Закладки") { panel = .bookmarks }
            navButton("clock", help: "История") { panel = .history }
            navButton("arrow.down.circle", help: "Загрузки") { panel = .downloads }
            navButton("gearshape", help: "Настройки") { openWindow(id: "settings") }
            navButton("macwindow.badge.plus", help: "Новое окно") { newWindow() }
            if let version = updateManager.availableVersion {
                Button {
                    Task { await updateManager.installUpdate() }
                } label: {
                    Label("Обновить", systemImage: "arrow.down.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help("Установить Delta \(version)")
            } else if updateManager.isBusy {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 26)
                    .help(updateManager.updateStatus)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    @ViewBuilder private var pageContent: some View {
        if let tab = store.selectedTab {
            if tab.isAbout {
                Color.white.ignoresSafeArea()
            } else if tab.isOffline {
                OfflineGameView()
            } else if let error = tab.loadError {
                NavigationErrorView(message: error, retry: { store.navigate(tab.address, in: tab) })
            } else if tab.isHome {
                StartPageView(store: store) { query in
                    addressText = query
                    store.navigate(query, in: tab)
                }
            } else {
                BrowserWebView(tab: tab, store: store)
                    .id(tab.id)
            }
        } else {
            Color.white
        }
    }

    private func navButton(_ symbol: String, help: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.45))
        .disabled(!enabled)
        .help(help)
    }

    private func newWindow() {
        openWindow(id: "main")
    }
}

private struct NavigationErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("Не удалось открыть страницу")
                .font(.title3.bold())
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
            Button("Повторить", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct WindowActivationObserver: NSViewRepresentable {
    let store: BrowserStore

    func makeNSView(context: Context) -> WindowActivationView {
        let view = WindowActivationView()
        view.activate = { BrowserStore.active = store }
        return view
    }

    func updateNSView(_ view: WindowActivationView, context: Context) {
        view.activate = { BrowserStore.active = store }
    }
}

private final class WindowActivationView: NSView {
    var activate: (() -> Void)?
    private var observer: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        guard let window else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.activate?()
        }
        if window.isKeyWindow { activate?() }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}

struct BrowserWebView: NSViewRepresentable {
    @ObservedObject var tab: BrowserTab
    let store: BrowserStore

    func makeCoordinator() -> BrowserWebCoordinator {
        BrowserWebCoordinator(store: store, tab: tab)
    }

    func makeNSView(context: Context) -> WKWebView {
        tab.webView.navigationDelegate = context.coordinator
        tab.webView.uiDelegate = context.coordinator
        return tab.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        nsView.navigationDelegate = context.coordinator
        nsView.uiDelegate = context.coordinator
    }
}

enum BrowserPanel: String, Identifiable {
    case bookmarks, history, downloads
    var id: String { rawValue }
    var title: String {
        switch self {
        case .bookmarks: return "Закладки"
        case .history: return "История"
        case .downloads: return "Загрузки"
        }
    }
}

struct BrowserPanelView: View {
    let panel: BrowserPanel
    @ObservedObject var store: BrowserStore
    @State private var search = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(panel.title).font(.title2.bold())
                Spacer()
                if panel == .downloads {
                    Button("Открыть папку") { store.openDownloadsFolder() }
                }
                if panel == .history {
                    Button("Очистить") { store.clearHistory() }
                }
                Button("Закрыть") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            if panel != .downloads {
                TextField("Поиск", text: $search)
                    .textFieldStyle(.roundedBorder)
            }
            List {
                switch panel {
                case .bookmarks:
                    ForEach(filtered(store.bookmarks)) { item in
                        row(title: item.title, subtitle: item.url) {
                            store.navigate(item.url)
                            dismiss()
                        }
                            .contextMenu { Button("Удалить") { store.removeBookmark(item) } }
                    }
                case .history:
                    ForEach(filtered(store.history)) { item in
                        row(title: item.title, subtitle: item.url) {
                            store.navigate(item.url)
                            dismiss()
                        }
                    }
                case .downloads:
                    ForEach(store.downloads) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Button(item.name) { if item.isComplete { store.openDownload(item) } }
                                .buttonStyle(.plain)
                            if item.isComplete {
                                Text(item.path).font(.caption).foregroundStyle(.secondary)
                            } else if let error = item.error {
                                Text(error).font(.caption).foregroundStyle(.red)
                            } else {
                                ProgressView(value: item.progress)
                                if item.expectedBytes > 0 {
                                    Text("\(ByteCountFormatter.string(fromByteCount: item.bytesWritten, countStyle: .file)) из \(ByteCountFormatter.string(fromByteCount: item.expectedBytes, countStyle: .file))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(18)
    }

    private func filtered(_ items: [BrowserItem]) -> [BrowserItem] {
        guard !search.isEmpty else { return items }
        return items.filter { $0.title.localizedCaseInsensitiveContains(search) ||
            $0.url.localizedCaseInsensitiveContains(search) }
    }

    private func row(title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}
