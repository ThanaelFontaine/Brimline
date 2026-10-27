import Foundation
import Testing
@testable import BrimlineCore

/// Answers from memory: a 302, an oversized body, or a normal one. Never touches the network.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var mode = "ok"
    nonisolated(unsafe) static var requested: [URL] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        Self.requested.append(url)
        switch Self.mode {
        case "redirect":
            let target = URL(string: "https://example.invalid/elsewhere")!
            let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: ["Location": target.absoluteString])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        case "big":
            let body = Data(count: URLSessionHTTPClient.maxBodyBytes + 1)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        default:
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("{}".utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

@Suite("Hardening", .serialized)
struct HardeningTests {
    func client() -> URLSessionHTTPClient { URLSessionHTTPClient(protocolClasses: [StubProtocol.self]) }
    func request() -> URLRequest { ClaudeUsageAPI.request(accessToken: "FAKE-TOKEN") }

    @Test("A 302 is not followed: it comes back as the answer")
    func redirectNotFollowed() async throws {
        StubProtocol.mode = "redirect"
        StubProtocol.requested = []
        do {
            let (_, response) = try await client().send(request())
            #expect(response.statusCode == 302)
        } catch {
            // Also acceptable: the final URL is not the usage URL.
        }
        #expect(!StubProtocol.requested.contains { $0.host == "example.invalid" })
    }

    @Test("A body over the limit fails the request")
    func bodyTooBig() async {
        StubProtocol.mode = "big"
        await #expect(throws: URLError.self) { _ = try await client().send(request()) }
    }

    @Test("A normal answer passes")
    func normal() async throws {
        StubProtocol.mode = "ok"
        let (data, response) = try await client().send(request())
        #expect(response.statusCode == 200 && data.count == 2)
    }

    @Test("A line over the limit is dropped, the next line is still handled")
    func longLine() {
        var splitter = BoundedLineSplitter(maxBytes: 1024 * 1024)
        let big = Data(repeating: 0x61, count: 2 * 1024 * 1024)
        var items = splitter.push(big.prefix(700_000))
        items += splitter.push(big.suffix(1_400_000))
        items += splitter.push(Data("\n{\"a\":1}\nlast".utf8))
        items += splitter.finish()
        #expect(items == [.tooLong, .line("{\"a\":1}"), .line("last")])
    }

    @Test("Lines split across chunks are joined")
    func chunks() {
        var splitter = BoundedLineSplitter(maxBytes: 100)
        var items = splitter.push(Data("ab".utf8))
        items += splitter.push(Data("c\nd\n".utf8))
        #expect(items == [.line("abc"), .line("d")])
    }

    @Test("Cache and settings: file 0600, folder 0700, even when the folder was 0755")
    func permissions() throws {
        let home = try TemporaryHome()
        let paths = BrimlinePaths(home: home.url)
        try FileManager.default.createDirectory(at: paths.supportDirectory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o755])
        try SettingsStore(file: paths.settingsFile).save(BrimlineSettings())
        try UsageCache(file: paths.cacheFile).save(UsageSnapshot(generatedAt: Date(), accounts: []))
        let fm = FileManager.default
        #expect(try fm.attributesOfItem(atPath: paths.supportDirectory.path)[.posixPermissions] as? Int == 0o700)
        for file in [paths.cacheFile, paths.settingsFile] {
            #expect(try fm.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int == 0o600)
        }
        let leftovers = try fm.contentsOfDirectory(atPath: paths.supportDirectory.path).filter { $0.hasSuffix(".tmp") }
        #expect(leftovers.isEmpty)
    }

    @Test("A failed write is thrown and leaves no temporary file")
    func failedWriteThrows() throws {
        let home = try TemporaryHome()
        let paths = BrimlinePaths(home: home.url)
        let target = paths.supportDirectory.appendingPathComponent("occupied")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        #expect(throws: (any Error).self) { try JSONCoding.write(Data("{}".utf8), to: target) }
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: paths.supportDirectory.path).filter { $0.hasSuffix(".tmp") }
        #expect(leftovers.isEmpty)
    }

    @Test("The temporary file is 0600 even under a permissive umask")
    func permissiveUmask() throws {
        let home = try TemporaryHome()
        let paths = BrimlinePaths(home: home.url)
        let previous = umask(0o277)
        defer { umask(previous) }
        try JSONCoding.write(Data("{}".utf8), to: paths.cacheFile)
        #expect(try FileManager.default.attributesOfItem(atPath: paths.cacheFile.path)[.posixPermissions] as? Int == 0o600)
    }

    @Test("run answers while the input stays open")
    func answersWithInputOpen() throws {
        let inPipe = Pipe(), outPipe = Pipe()
        let server = MCPServer(version: "0.0.0", load: { (nil, BrimlineSettings()) })
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            server.run(input: inPipe.fileHandleForReading, output: outPipe.fileHandleForWriting)
            done.signal()
        }
        let reader = outPipe.fileHandleForReading
        for id in [1, 2] {
            inPipe.fileHandleForWriting.write(Data("{\"jsonrpc\":\"2.0\",\"id\":\(id),\"method\":\"ping\"}\n".utf8))
            var pollfd = pollfd(fd: reader.fileDescriptor, events: Int16(POLLIN), revents: 0)
            #expect(poll(&pollfd, 1, 5000) == 1, "no answer within 5 s while stdin is open")
            var bytes = [UInt8](repeating: 0, count: 4096)
            let count = read(reader.fileDescriptor, &bytes, bytes.count)
            #expect(count > 0)
            #expect(String(decoding: bytes[0..<max(count, 0)], as: UTF8.self).contains("\"id\":\(id)"))
        }
        try inPipe.fileHandleForWriting.close()
        #expect(done.wait(timeout: .now() + 5) == .success)
    }

    @Test("run(input:output:) answers -32600 to a too long line, then handles the next one")
    func runEndToEnd() throws {
        let inPipe = Pipe(), outPipe = Pipe()
        let writer = inPipe.fileHandleForWriting
        let line = Data(repeating: 0x61, count: MCPServer.maxLineBytes + 10)
        let next = Data("\n{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"ping\"}\n".utf8)
        DispatchQueue.global().async {
            writer.write(line)
            writer.write(next)
            try? writer.close()
        }
        let server = MCPServer(version: "0.0.0", load: { (nil, BrimlineSettings()) })
        server.run(input: inPipe.fileHandleForReading, output: outPipe.fileHandleForWriting)
        try outPipe.fileHandleForWriting.close()
        let text = String(decoding: outPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let lines = text.split(separator: "\n").map(String.init)
        #expect(lines.count == 2)
        #expect(lines[0].contains("-32600") && lines[0].contains("\"id\":null"))
        #expect(lines[1].contains("\"id\":7"))
    }
}
