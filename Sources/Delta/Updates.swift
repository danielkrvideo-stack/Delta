import AppKit
import Combine
import CryptoKit
import Foundation

struct DeltaRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let name: String?
    let body: String?
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name, body, draft, prerelease, assets
    }
}

@MainActor
final class UpdateManager: ObservableObject {
    enum State {
        case idle
        case checking
        case current
        case available(version: String, archiveURL: URL, checksumURL: URL)
        case downloading
        case installing
        case failed(String)
    }

    static let shared = UpdateManager()

    @Published private(set) var state: State = .idle
    @Published private(set) var updateStatus = ""

    private let repository = "danielkrvideo-stack/Delta"
    private let archiveName = "Delta-macos-intel.zip"
    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 300
        session = URLSession(configuration: configuration)
    }

    var availableVersion: String? {
        guard case let .available(version, _, _) = state else { return nil }
        return version
    }

    var isBusy: Bool {
        switch state {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }

    func checkForUpdates(showStatus: Bool = false) async {
        guard !isBusy else { return }
        state = .checking
        if showStatus { updateStatus = "Проверка обновлений…" }

        do {
            let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Delta-macOS", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw UpdateError.invalidResponse
            }
            if http.statusCode == 404 {
                state = .current
                updateStatus = "Пока нет опубликованных релизов."
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                throw UpdateError.server("GitHub вернул HTTP \(http.statusCode).")
            }

            let release = try JSONDecoder().decode(DeltaRelease.self, from: data)
            guard !release.draft, !release.prerelease,
                  let latestVersion = SemanticVersion(release.tagName) else {
                throw UpdateError.invalidRelease
            }
            let currentVersionString = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
            guard let currentVersion = SemanticVersion(currentVersionString) else {
                throw UpdateError.invalidVersion
            }
            guard latestVersion > currentVersion else {
                state = .current
                updateStatus = "Установлена последняя версия."
                return
            }

            guard let archive = release.assets.first(where: { $0.name == archiveName }),
                  let checksum = release.assets.first(where: { $0.name == archiveName + ".sha256" }),
                  isTrustedGitHubURL(archive.browserDownloadURL),
                  isTrustedGitHubURL(checksum.browserDownloadURL) else {
                throw UpdateError.missingAssets
            }
            state = .available(
                version: latestVersion.description,
                archiveURL: archive.browserDownloadURL,
                checksumURL: checksum.browserDownloadURL
            )
            updateStatus = "Доступно обновление \(latestVersion)."
        } catch {
            NSLog("Delta update check failed: %@", error.localizedDescription)
            state = .failed(error.localizedDescription)
            updateStatus = error.localizedDescription
        }
    }

    func installUpdate() async {
        guard case let .available(version, archiveURL, checksumURL) = state else { return }
        state = .downloading
        updateStatus = "Скачивание обновления \(version)…"

        do {
            let (checksumData, checksumResponse) = try await session.data(from: checksumURL)
            try validate(checksumResponse)
            guard let expectedHash = String(data: checksumData, encoding: .utf8)?
                .split(whereSeparator: \.isWhitespace).first?
                .lowercased(),
                  expectedHash.count == 64,
                  expectedHash.allSatisfy(\.isHexDigit) else {
                throw UpdateError.invalidChecksum
            }

            let (temporaryURL, archiveResponse) = try await session.download(from: archiveURL)
            try validate(archiveResponse)
            let fileSize = try temporaryURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard fileSize > 0, fileSize <= 100 * 1024 * 1024 else {
                try? FileManager.default.removeItem(at: temporaryURL)
                throw UpdateError.invalidArchiveSize
            }
            let archiveURLOnDisk = FileManager.default.temporaryDirectory
                .appendingPathComponent("Delta-update-\(UUID().uuidString).zip")
            try FileManager.default.moveItem(at: temporaryURL, to: archiveURLOnDisk)
            let archiveData = try Data(contentsOf: archiveURLOnDisk, options: .mappedIfSafe)
            let actualHash = SHA256.hash(data: archiveData).map { String(format: "%02x", $0) }.joined()
            guard actualHash == expectedHash else {
                try? FileManager.default.removeItem(at: archiveURLOnDisk)
                throw UpdateError.checksumMismatch
            }

            let installerURL = Bundle.main.bundleURL
                .appendingPathComponent("Contents/MacOS/DeltaUpdateInstaller")
            guard FileManager.default.isExecutableFile(atPath: installerURL.path) else {
                try? FileManager.default.removeItem(at: archiveURLOnDisk)
                throw UpdateError.installerMissing
            }

            let process = Process()
            process.executableURL = installerURL
            process.arguments = [
                "--archive", archiveURLOnDisk.path,
                "--target", Bundle.main.bundleURL.path,
                "--pid", String(ProcessInfo.processInfo.processIdentifier)
            ]
            try process.run()
            state = .installing
            updateStatus = "Delta завершится и откроется после установки обновления."
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                NSApp.terminate(nil)
            }
        } catch {
            NSLog("Delta update installation failed: %@", error.localizedDescription)
            state = .failed(error.localizedDescription)
            updateStatus = error.localizedDescription
        }
    }

    private func validate(_ response: URLResponse) throws {
        guard let url = response.url, isTrustedGitHubURL(url),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw UpdateError.downloadFailed
        }
    }

    private func isTrustedGitHubURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased() else { return false }
        return host == "github.com" ||
            host == "objects.githubusercontent.com" ||
            host == "release-assets.githubusercontent.com"
    }
}

private struct SemanticVersion: Comparable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ rawValue: String) {
        let clean = rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        let components = clean.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(components.count),
              let major = Int(components[0]),
              let minor = Int(components[1]),
              components.dropFirst(2).first.map({ Int($0) != nil }) ?? true else { return nil }
        self.major = major
        self.minor = minor
        self.patch = components.count == 3 ? Int(components[2])! : 0
    }

    var description: String { "\(major).\(minor).\(patch)" }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

private enum UpdateError: LocalizedError {
    case invalidResponse
    case server(String)
    case invalidRelease
    case invalidVersion
    case missingAssets
    case invalidChecksum
    case checksumMismatch
    case downloadFailed
    case invalidArchiveSize
    case installerMissing

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Сервер обновлений вернул некорректный ответ."
        case let .server(message): return message
        case .invalidRelease: return "Не удалось прочитать версию релиза Delta."
        case .invalidVersion: return "Текущая версия Delta указана некорректно."
        case .missingAssets: return "В релизе отсутствует архив обновления для Intel Mac."
        case .invalidChecksum: return "Файл контрольной суммы обновления повреждён."
        case .checksumMismatch: return "Контрольная сумма обновления не совпала. Установка отменена."
        case .downloadFailed: return "Не удалось скачать обновление."
        case .invalidArchiveSize: return "Размер архива обновления недопустим."
        case .installerMissing: return "В приложении не найден установщик обновлений. Пересоберите Delta."
        }
    }
}
