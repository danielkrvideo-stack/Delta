import AppKit
import Foundation

struct InstallerArguments {
    let archive: URL
    let target: URL
    let processID: pid_t

    init(arguments: [String]) throws {
        guard arguments.count == 6,
              arguments[0] == "--archive",
              arguments[2] == "--target",
              arguments[4] == "--pid",
              let processID = pid_t(arguments[5]),
              processID > 0 else {
            throw InstallerError.invalidArguments
        }
        archive = URL(fileURLWithPath: arguments[1]).standardizedFileURL
        target = URL(fileURLWithPath: arguments[3]).standardizedFileURL
        self.processID = processID
    }
}

enum InstallerError: LocalizedError {
    case invalidArguments
    case appNotStopped
    case targetNotWritable
    case archiveMissing
    case appMissing
    case wrongBundle
    case replacementFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments: return "Параметры установщика обновления некорректны."
        case .appNotStopped: return "Delta не завершилась. Обновление не установлено."
        case .targetNotWritable: return "Нет прав для обновления этой папки. Переместите Delta в папку «Программы» пользователя."
        case .archiveMissing: return "Архив обновления не найден."
        case .appMissing: return "В архиве отсутствует Delta.app."
        case .wrongBundle: return "Архив содержит не приложение Delta."
        case let .replacementFailed(message): return "Не удалось заменить Delta: \(message)"
        }
    }
}

func showError(_ message: String) {
    let alert = NSAlert()
    alert.messageText = "Не удалось обновить Delta"
    alert.informativeText = message
    alert.alertStyle = .warning
    alert.addButton(withTitle: "OK")
    alert.runModal()
}

func run(_ arguments: InstallerArguments) throws {
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: arguments.archive.path) else {
        throw InstallerError.archiveMissing
    }

    let parent = arguments.target.deletingLastPathComponent()
    guard fileManager.isWritableFile(atPath: parent.path) else {
        throw InstallerError.targetNotWritable
    }

    let deadline = Date().addingTimeInterval(120)
    while kill(arguments.processID, 0) == 0, Date() < deadline {
        Thread.sleep(forTimeInterval: 0.25)
    }
    guard kill(arguments.processID, 0) != 0, errno == ESRCH else {
        throw InstallerError.appNotStopped
    }

    let staging = parent.appendingPathComponent(".Delta-update-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
    defer { try? fileManager.removeItem(at: staging) }

    let ditto = Process()
    ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    ditto.arguments = ["-x", "-k", arguments.archive.path, staging.path]
    try ditto.run()
    ditto.waitUntilExit()
    guard ditto.terminationStatus == 0 else {
        throw InstallerError.replacementFailed("Архив не удалось распаковать.")
    }

    let extractedApp = staging.appendingPathComponent("Delta.app", isDirectory: true)
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: extractedApp.path, isDirectory: &isDirectory), isDirectory.boolValue else {
        throw InstallerError.appMissing
    }

    let infoURL = extractedApp.appendingPathComponent("Contents/Info.plist")
    guard let info = NSDictionary(contentsOf: infoURL) as? [String: Any],
          info["CFBundleIdentifier"] as? String == "com.delta.browser",
          let executable = info["CFBundleExecutable"] as? String,
          fileManager.isExecutableFile(atPath: extractedApp.appendingPathComponent("Contents/MacOS/\(executable)").path) else {
        throw InstallerError.wrongBundle
    }
    let architectureCheck = Process()
    architectureCheck.executableURL = URL(fileURLWithPath: "/usr/bin/lipo")
    architectureCheck.arguments = [
        extractedApp.appendingPathComponent("Contents/MacOS/\(executable)").path,
        "-verify_arch",
        "x86_64"
    ]
    try architectureCheck.run()
    architectureCheck.waitUntilExit()
    guard architectureCheck.terminationStatus == 0 else {
        throw InstallerError.wrongBundle
    }

    let backup = parent.appendingPathComponent(".Delta-backup-\(UUID().uuidString)", isDirectory: true)
    do {
        try fileManager.moveItem(at: arguments.target, to: backup)
        do {
            try fileManager.moveItem(at: extractedApp, to: arguments.target)
        } catch {
            try? fileManager.moveItem(at: backup, to: arguments.target)
            throw error
        }
        try fileManager.removeItem(at: backup)
    } catch {
        throw InstallerError.replacementFailed(error.localizedDescription)
    }

    try? fileManager.removeItem(at: arguments.archive)
    let launcher = Process()
    launcher.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    launcher.arguments = ["-n", arguments.target.path]
    try launcher.run()
    launcher.waitUntilExit()
    guard launcher.terminationStatus == 0 else {
        throw InstallerError.replacementFailed("Обновлённую Delta не удалось запустить.")
    }
}

do {
    let arguments = try InstallerArguments(arguments: Array(CommandLine.arguments.dropFirst()))
    try run(arguments)
} catch {
    showError(error.localizedDescription)
    exit(EXIT_FAILURE)
}
