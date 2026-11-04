import Foundation
import Security
import Testing
@testable import BrimlineCore

/// The real check of Google's signature (Security.framework), on programs that are not Google's: no certificate of
/// Google's is needed, and nothing here reads the real `~/.local/bin/agy` unless `BRIMLINE_REAL_AGY=1` (never in CI).
@Suite("Gemini through Antigravity: the check of Google's signature")
struct AntigravitySignatureTests {
    /// A folder of the test, removed afterwards.
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("brimline-sign-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func codesign(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "codesign \(arguments)")
    }

    private let google = SecurityFrameworkCodeChecker()
    private let ls = URL(fileURLWithPath: "/bin/ls")

    @Test("The requirement is exactly Google's, as read on agy 1.4.11, and the system accepts it")
    func requirementText() {
        #expect(SecurityFrameworkCodeChecker.google == "identifier \"cli\" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] and certificate leaf[field.1.2.840.113635.100.6.1.13] and certificate leaf[subject.OU] = \"EQHXZ8M8AV\"")
        #expect(SecurityFrameworkCodeChecker.google.contains("EQHXZ8M8AV"))
        // Team AND identifier: never the team alone.
        #expect(SecurityFrameworkCodeChecker.google.hasPrefix("identifier \"cli\" and "))
        // Not in it: `notarized` (not documented in Apple's language), the online revocation check.
        #expect(!SecurityFrameworkCodeChecker.google.contains("notarized"))
        for text in [SecurityFrameworkCodeChecker.google, SecurityFrameworkCodeChecker.googleAnyIdentifier] {
            var requirement: SecRequirement?
            #expect(SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess && requirement != nil)
        }
        #expect(!SecurityFrameworkCodeChecker.googleAnyIdentifier.contains("identifier"))
    }

    @Test("The checks are the strict ones, on every architecture, with no network: no revocation check")
    func flags() {
        let raw = SecurityFrameworkCodeChecker.flags.rawValue
        #expect(raw & UInt32(kSecCSCheckAllArchitectures) != 0)
        #expect(raw & UInt32(kSecCSStrictValidate) != 0)
        #expect(raw & (1 << 29) != 0)                              // kSecCSNoNetworkAccess
        #expect(raw & (1 << 30) == 0)                       // kSecCSEnforceRevocationChecks: would ask the network
        #expect(raw & UInt32(kSecCSCheckNestedCode) == 0)          // a bare Mach-O has none
    }

    @Test("A shell script is unsigned")
    func script() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let script = dir.appendingPathComponent("agy")
        try Data("#!/bin/sh\necho hello\n".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        #expect(google.checkStatic(at: script) == .unsigned)
    }

    @Test("A signed program that is not Google's (Apple's ls, or a copy of it signed ad hoc) does not satisfy Google's requirement")
    func notGoogle() throws {
        #expect(google.checkStatic(at: ls) == .requirementFailed)
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let copy = dir.appendingPathComponent("agy")
        try FileManager.default.copyItem(at: ls, to: copy)
        try codesign(["-f", "-s", "-", "-i", "cli", copy.path])   // even with the identifier `cli`
        #expect(google.checkStatic(at: copy) == .requirementFailed)
        #expect(!google.isOtherIdentifier(at: copy))
    }

    @Test("A path with nothing is not accepted")
    func missing() {
        #expect(google.checkStatic(at: URL(fileURLWithPath: "/nonexistent/agy")) == .unreadable)
    }

    @Test("The requirement checks the identifier as well as the anchor: com.apple.ls passes, com.apple.cat does not")
    func identifierMatters() {
        let anchorAndLs = SecurityFrameworkCodeChecker(requirement: "anchor apple and identifier \"com.apple.ls\"")
        let anchorAndCat = SecurityFrameworkCodeChecker(requirement: "anchor apple and identifier \"com.apple.cat\"")
        #expect(anchorAndLs.checkStatic(at: ls) == .accepted)
        #expect(anchorAndCat.checkStatic(at: ls) == .requirementFailed)
    }

    @Test("\"Right team, other identifier\" is told apart: the looser requirement passes where the exact one fails")
    func otherIdentifier() {
        let checker = SecurityFrameworkCodeChecker(requirement: "anchor apple and identifier \"com.apple.cat\"",
                                                   withoutIdentifier: "anchor apple")
        #expect(checker.checkStatic(at: ls) == .requirementFailed)
        #expect(checker.isOtherIdentifier(at: ls))
        // Google's own, on a program that is not Google's: the looser one fails too.
        #expect(!google.isOtherIdentifier(at: ls))
        // A requirement with no looser form never says it.
        #expect(!SecurityFrameworkCodeChecker(requirement: "anchor apple").isOtherIdentifier(at: ls))
    }

    @Test("The real agy, on the Mac that has it: only with BRIMLINE_REAL_AGY=1 (never in CI)",
          .enabled(if: ProcessInfo.processInfo.environment["BRIMLINE_REAL_AGY"] == "1"))
    func realAgy() {
        let real = AntigravityBinary.url(home: FileManager.default.homeDirectoryForCurrentUser)
        #expect(google.checkStatic(at: real) == .accepted)
    }
}
