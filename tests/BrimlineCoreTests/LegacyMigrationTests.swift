import CryptoKit
import Foundation
import Testing
@testable import BrimlineCore

@Suite("Migration from the Sightglass folder")
struct LegacyMigrationTests {
    static let settingsJSON = #"{"schemaVersion":1,"labels":{"abc":"Work"},"hiddenAccounts":["x"],"refreshMinutes":10}"#
    static let usageJSON = #"{"schemaVersion":1,"generatedAt":"2026-10-26T10:00:00Z","accounts":[]}"#

    let home: TemporaryHome
    let paths: BrimlinePaths

    init() throws {
        home = try TemporaryHome()
        paths = BrimlinePaths(home: home.url)
    }

    var legacy: String { "Library/Application Support/Sightglass" }
    var current: String { "Library/Application Support/Brimline" }

    func legacyFolder() throws {
        try home.write("\(legacy)/settings.json", Self.settingsJSON)
        try home.write("\(legacy)/usage.json", Self.usageJSON)
    }

    func mode(_ relative: String) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: home.url.appendingPathComponent(relative).path)
        return (attributes[.posixPermissions] as! NSNumber).intValue
    }

    func exists(_ relative: String) -> Bool {
        var status = stat()
        return lstat(home.url.appendingPathComponent(relative).path, &status) == 0
    }

    /// A fingerprint of every file of a folder (name and content), to prove it did not change.
    func fingerprint(_ relative: String) throws -> [String: String] {
        let folder = home.url.appendingPathComponent(relative)
        var result: [String: String] = [:]
        for name in try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() {
            let data = try Data(contentsOf: folder.appendingPathComponent(name))
            result[name] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        return result
    }

    @Test("Simple migration: both files come over, same content, 0700 and 0600, marker written")
    func simple() throws {
        try legacyFolder()
        let outcome = LegacyMigration.run(paths: paths)
        #expect(outcome.copied == ["settings.json", "usage.json"])
        #expect(outcome.done)
        let settings = try #require(SettingsStore(file: paths.settingsFile).load() as BrimlineSettings?)
        #expect(settings.labels == ["abc": "Work"])
        #expect(settings.hiddenAccounts == ["x"])
        #expect(settings.refreshMinutes == 10)
        #expect(UsageCache(file: paths.cacheFile).load()?.accounts.isEmpty == true)
        #expect(try mode(current) == 0o700)
        #expect(try mode("\(current)/settings.json") == 0o600)
        #expect(try mode("\(current)/usage.json") == 0o600)
        #expect(exists("\(current)/\(LegacyMigration.markerName)"))
    }

    @Test("No old folder: nothing to copy, the marker is written")
    func noLegacyFolder() throws {
        let outcome = LegacyMigration.run(paths: paths)
        #expect(outcome.copied.isEmpty)
        #expect(outcome.done)
        #expect(exists("\(current)/\(LegacyMigration.markerName)"))
        #expect(!exists("\(current)/settings.json"))
    }

    @Test("Marker present: nothing moves, even if the old folder has files")
    func markerPresent() throws {
        try legacyFolder()
        try home.write("\(current)/\(LegacyMigration.markerName)", "done\n")
        let outcome = LegacyMigration.run(paths: paths)
        #expect(outcome.copied.isEmpty)
        #expect(outcome.done)
        #expect(!exists("\(current)/settings.json"))
        #expect(!exists("\(current)/usage.json"))
    }

    @Test("A file already in the new folder is never replaced")
    func destinationPresent() throws {
        try legacyFolder()
        let mine = #"{"schemaVersion":1,"refreshMinutes":15}"#
        try home.write("\(current)/settings.json", mine)
        let outcome = LegacyMigration.run(paths: paths)
        #expect(outcome.copied == ["usage.json"])
        #expect(outcome.done)
        #expect(try String(contentsOf: paths.settingsFile, encoding: .utf8) == mine)
    }

    @Test("Links are refused: a linked old folder, and a linked file inside it")
    func symbolicLinks() throws {
        // A linked folder: nothing is read, nothing is written, not even the marker.
        try home.write("elsewhere/settings.json", Self.settingsJSON)
        try home.mkdir("Library/Application Support")
        try FileManager.default.createSymbolicLink(
            atPath: home.url.appendingPathComponent(legacy).path,
            withDestinationPath: home.url.appendingPathComponent("elsewhere").path)
        let linkedFolder = LegacyMigration.run(paths: paths)
        #expect(linkedFolder.copied.isEmpty)
        #expect(!linkedFolder.done)
        #expect(!exists(current))

        // A linked file inside a real folder: that file is left behind, the other one comes over.
        try FileManager.default.removeItem(at: home.url.appendingPathComponent(legacy))
        try home.write("\(legacy)/usage.json", Self.usageJSON)
        try FileManager.default.createSymbolicLink(
            atPath: home.url.appendingPathComponent("\(legacy)/settings.json").path,
            withDestinationPath: home.url.appendingPathComponent("elsewhere/settings.json").path)
        let linkedFile = LegacyMigration.run(paths: paths)
        #expect(linkedFile.copied == ["usage.json"])
        #expect(!exists("\(current)/settings.json"))
    }

    @Test("Invalid JSON is ignored, the other file still comes over")
    func invalidJSON() throws {
        try home.write("\(legacy)/settings.json", "{not json")
        try home.write("\(legacy)/usage.json", Self.usageJSON)
        let outcome = LegacyMigration.run(paths: paths)
        #expect(outcome.copied == ["usage.json"])
        #expect(outcome.done)
        #expect(!exists("\(current)/settings.json"))
    }

    @Test("A file of more than 1 MiB is ignored")
    func tooBig() throws {
        let padding = String(repeating: "a", count: (1 << 20) + 10)
        try home.write("\(legacy)/settings.json", #"{"schemaVersion":1,"labels":{"abc":"\#(padding)"}}"#)
        try home.write("\(legacy)/usage.json", Self.usageJSON)
        let outcome = LegacyMigration.run(paths: paths)
        #expect(outcome.copied == ["usage.json"])
        #expect(!exists("\(current)/settings.json"))
    }

    @Test("A partial failure leaves no marker, and the next launch completes it")
    func partialFailure() throws {
        try legacyFolder()
        let first = LegacyMigration.run(paths: paths) { data, url in
            if url.lastPathComponent == "usage.json" { throw POSIXError(.EIO) }
            try JSONCoding.write(data, to: url, replacing: false)
        }
        #expect(first.copied == ["settings.json"])
        #expect(!first.done)
        #expect(!exists("\(current)/\(LegacyMigration.markerName)"))

        let second = LegacyMigration.run(paths: paths)
        #expect(second.copied == ["usage.json"])
        #expect(second.done)
        #expect(exists("\(current)/\(LegacyMigration.markerName)"))
    }

    @Test("Two calls at the same time give one result and replace nothing")
    func concurrentCalls() throws {
        try legacyFolder()
        DispatchQueue.concurrentPerform(iterations: 8) { _ in
            LegacyMigration.run(paths: paths)
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: paths.supportDirectory.path).sorted()
        #expect(names == [LegacyMigration.markerName, "settings.json", "usage.json"])
        #expect(SettingsStore(file: paths.settingsFile).load().labels == ["abc": "Work"])
        #expect(UsageCache(file: paths.cacheFile).load() != nil)
    }

    @Test("The old folder is left exactly as it was")
    func legacyUntouched() throws {
        try legacyFolder()
        try home.write("\(legacy)/other.txt", "kept")
        let before = try fingerprint(legacy)
        let modeBefore = try mode(legacy)
        LegacyMigration.run(paths: paths)
        LegacyMigration.run(paths: paths)
        #expect(try fingerprint(legacy) == before)
        #expect(try mode(legacy) == modeBefore)
        #expect(!exists("\(current)/other.txt"))
    }

    @Test("A file that appears between the check and the write is never replaced (RENAME_EXCL)")
    func raceAfterTheCheck() throws {
        try legacyFolder()
        let mine = #"{"schemaVersion":1,"refreshMinutes":15}"#
        let outcome = LegacyMigration.run(paths: paths) { data, url in
            // Another launch (the app or the command) wins the race right before this write.
            if url.lastPathComponent == "settings.json" { try self.home.write("\(self.current)/settings.json", mine) }
            try JSONCoding.write(data, to: url, replacing: false)
        }
        #expect(outcome.copied == ["usage.json"])
        #expect(outcome.done)
        #expect(try String(contentsOf: paths.settingsFile, encoding: .utf8) == mine)
        let names = try FileManager.default.contentsOfDirectory(atPath: paths.supportDirectory.path).sorted()
        #expect(names == [LegacyMigration.markerName, "settings.json", "usage.json"])
    }

    @Test("JSONCoding.write with replacing: false throws EEXIST, keeps the file and leaves no temporary file")
    func exclusiveWrite() throws {
        let file = home.url.appendingPathComponent("\(current)/settings.json")
        try home.write("\(current)/settings.json", "first")
        #expect(throws: POSIXError.self) { try JSONCoding.write(Data("second".utf8), to: file, replacing: false) }
        #expect(try String(contentsOf: file, encoding: .utf8) == "first")
        #expect(try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path) == ["settings.json"])
        try JSONCoding.write(Data("third".utf8), to: file)
        #expect(try String(contentsOf: file, encoding: .utf8) == "third")
    }
}
