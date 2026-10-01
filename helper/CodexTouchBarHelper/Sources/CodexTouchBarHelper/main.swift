import AppKit
import CodexTouchBarCore
import Foundation
import Darwin

let arguments = Set(CommandLine.arguments.dropFirst())
let configuration = UsageStoreConfiguration()

if arguments.contains("--zcode-once-json") {
    let store = ZCodeUsageStore()
    _ = await store.refreshLocal()
    let snapshot = arguments.contains("--no-remote")
        ? await store.cachedSnapshot()
        : await store.refreshRemote()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    FileHandle.standardOutput.write(try encoder.encode(snapshot))
    FileHandle.standardOutput.write(Data("\n".utf8))
    exit(0)
}

if arguments.contains("--rebuild-token-stats") {
    let stats = TokenStatsStore(
        codexHome: configuration.codexHome,
        cacheFile: configuration.tokenStatsCacheFile
    ).load(fullScan: true)
    let data = try JSONEncoder().encode(stats)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
    exit(0)
}

if arguments.contains("--once-json") {
    do {
        let snapshot = try await UsageStore(configuration: configuration).resolveUsage(
            allowRemote: !arguments.contains("--no-remote"),
            cacheMaxAge: arguments.contains("--no-remote") ? 60 : 0
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
        exit(0)
    } catch {
        fputs("CodexTouchBarHelper: \(error.localizedDescription)\n", stderr)
        exit(2)
    }
}

// Hold an advisory lock for the lifetime of the GUI, across every bundle copy.
// Command-line probes above do not compete with the running application.
let lockDirectory = configuration.cacheFile.deletingLastPathComponent()
try FileManager.default.createDirectory(at: lockDirectory, withIntermediateDirectories: true)
let instanceLock = open(lockDirectory.appendingPathComponent("helper.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
guard instanceLock >= 0 else {
    fputs("CodexTouchBarHelper: unable to open instance lock\n", stderr)
    exit(2)
}
guard flock(instanceLock, LOCK_EX | LOCK_NB) == 0 else {
    close(instanceLock)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate(configuration: configuration)
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
