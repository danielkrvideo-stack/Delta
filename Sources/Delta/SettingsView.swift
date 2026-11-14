import AppKit
import SwiftUI
import WebKit

struct SettingsView: View {
    @AppStorage("delta.homepage") private var homepage = "https://www.google.com"
    @AppStorage("delta.searchEngine") private var searchEngine = "Google"
    @AppStorage("delta.newTabMode") private var newTabMode = "home"
    @AppStorage("delta.startupMode") private var startupMode = "restore"
    @AppStorage("delta.theme") private var theme = "Системная"
    @AppStorage("delta.zoom") private var zoom = 1.0
    @AppStorage("delta.downloadFolder") private var downloadFolder = NSHomeDirectory() + "/Downloads"
    @State private var selectedSection = 0
    @State private var message: String?

    var body: some View {
        VStack(spacing: 0) {
            Picker("Раздел настроек", selection: $selectedSection) {
                Text("Основные").tag(0)
                Text("Внешний вид").tag(1)
                Text("Приватность").tag(2)
                Text("Загрузки").tag(3)
            }
            .pickerStyle(.segmented)
            .padding(18)
            Divider()
            Form {
                switch selectedSection {
                case 0:
                    Section("Основные") {
                        TextField("Домашняя страница", text: $homepage)
                        Picker("Поисковая система", selection: $searchEngine) {
                            Text("Google").tag("Google")
                            Text("DuckDuckGo").tag("DuckDuckGo")
                            Text("Bing").tag("Bing")
                        }
                        Picker("Новая вкладка", selection: $newTabMode) {
                            Text("Стартовая страница").tag("home")
                            Text("Пустая страница (about)").tag("about")
                        }
                        Picker("При запуске", selection: $startupMode) {
                            Text("Восстановить вкладки").tag("restore")
                            Text("Открыть стартовую страницу").tag("home")
                            Text("Открыть домашнюю страницу").tag("homepage")
                        }
                    }
                case 1:
                    Section("Внешний вид") {
                        Picker("Тема", selection: $theme) {
                            Text("Системная").tag("Системная")
                            Text("Светлая").tag("Светлая")
                            Text("Тёмная").tag("Тёмная")
                        }
                        HStack {
                            Text("Масштаб интерфейса")
                            Slider(value: $zoom, in: 0.8...1.2, step: 0.05)
                            Text("\(Int(zoom * 100))%").monospacedDigit().frame(width: 42)
                        }
                    }
                case 2:
                    Section("Приватность") {
                        Button("Очистить историю посещений") {
                            BrowserStore.sharedClearHistory()
                            message = "История посещений очищена."
                        }
                        Button("Очистить cookies") {
                            clear(types: ["WKWebsiteDataTypeCookies"])
                        }
                        Button("Очистить кэш") {
                            clear(types: ["WKWebsiteDataTypeDiskCache", "WKWebsiteDataTypeMemoryCache"])
                        }
                        Button("Очистить все данные сайтов", role: .destructive) {
                            clear(types: nil)
                        }
                    }
                default:
                    Section("Загрузки") {
                        HStack {
                            Text(downloadFolder).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button("Выбрать…") { chooseFolder() }
                        }
                        Button("Открыть папку загрузок") {
                            NSWorkspace.shared.open(URL(fileURLWithPath: downloadFolder, isDirectory: true))
                        }
                    }
                }
            }
            .formStyle(.grouped)
            Spacer(minLength: 0)
            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary).padding(.bottom, 10)
            }
        }
    }

    private func clear(types: Set<String>?) {
        let allTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        let selected = types.map { Set($0) } ?? allTypes
        WKWebsiteDataStore.default().removeData(ofTypes: selected, modifiedSince: .distantPast) {
            message = "Данные сайтов очищены."
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Выбрать"
        if panel.runModal() == .OK, let url = panel.url {
            downloadFolder = url.path
        }
    }
}

private extension BrowserStore {
    static func sharedClearHistory() {
        UserDefaults.standard.removeObject(forKey: "delta.history")
        NotificationCenter.default.post(name: .deltaClearHistory, object: nil)
    }
}
