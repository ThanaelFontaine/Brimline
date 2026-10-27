import CryptoKit
import Foundation

/// The shape of a provider's answer: its keys and the types of its values, never a value.
///
/// Four of the five providers are read through endpoints nobody documents. When one changes, the
/// fingerprint changes (it is kept in the cache) and the skeleton tells the maintainer what the
/// answer looks like now.
public enum ResponseShape {
    static let maxDepth = 8
    static let maxKeys = 2000

    /// SHA-256 (hex) of the sorted key paths of a JSON answer, such as `limits[].percent`. Empty when
    /// the answer is not JSON. No value goes into it.
    public static func fingerprint(of data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return "" }
        var paths = Set<String>()
        collect(object, prefix: "", depth: 0, into: &paths)
        let joined = paths.sorted().joined(separator: "\n")
        return SHA256.hash(data: Data(joined.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func collect(_ value: Any, prefix: String, depth: Int, into paths: inout Set<String>) {
        guard depth < maxDepth, paths.count < maxKeys else { return }
        if let dictionary = value as? [String: Any] {
            for (key, child) in dictionary {
                let path = prefix.isEmpty ? key : "\(prefix).\(key)"
                paths.insert(path)
                collect(child, prefix: path, depth: depth + 1, into: &paths)
            }
        } else if let array = value as? [Any] {
            for child in array { collect(child, prefix: prefix + "[]", depth: depth + 1, into: &paths) }
        }
    }

    /// The answer with every value replaced by its type (`"string"`, `"number"`, `"bool"`, `"null"`), as
    /// indented JSON. An array shows its first element only. A key that does not pass
    /// `ProviderText.label` is written `"?"`. Nil when the answer is not JSON.
    public static func skeleton(of data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return render(object, depth: 0, indent: "")
    }

    private static func render(_ value: Any, depth: Int, indent: String) -> String {
        if depth >= maxDepth { return "\"...\"" }
        let inner = indent + "  "
        if let dictionary = value as? [String: Any] {
            if dictionary.isEmpty { return "{}" }
            let keys = dictionary.keys.sorted().prefix(100)
            var lines = keys.map { key -> String in
                let name = ProviderText.label(key) ?? "?"
                return "\(inner)\"\(name)\": \(render(dictionary[key]!, depth: depth + 1, indent: inner))"
            }
            if dictionary.count > 100 { lines.append("\(inner)\"...\": \"more keys\"") }
            return "{\n" + lines.joined(separator: ",\n") + "\n\(indent)}"
        }
        if let array = value as? [Any] {
            guard let first = array.first else { return "[]" }
            return "[\(render(first, depth: depth + 1, indent: indent))]"
        }
        if value is NSNull { return "\"null\"" }
        if let number = value as? NSNumber {
            return CFGetTypeID(number) == CFBooleanGetTypeID() ? "\"bool\"" : "\"number\""
        }
        return "\"string\""
    }
}

/// Wraps a client and remembers the last answer of each URL, for `brimline status --live --shape`.
/// The answers stay in memory, are only used to draw a skeleton, and are never written.
public final class RecordingHTTPClient: HTTPClient, @unchecked Sendable {
    private let base: any HTTPClient
    private let lock = NSLock()
    private var bodies: [String: Data] = [:]

    public init(_ base: any HTTPClient = URLSessionHTTPClient()) { self.base = base }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await base.send(request)
        if let url = request.url {
            // The address without its query: the skeleton names the endpoint, nothing else.
            var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
            parts?.query = nil
            lock.withLock { bodies[parts?.string ?? url.absoluteString] = data }
        }
        return (data, response)
    }

    /// The skeleton of the last answer of each URL, by URL.
    public var skeletons: [(url: String, skeleton: String)] {
        lock.withLock { bodies.sorted { $0.key < $1.key } }
            .compactMap { entry in ResponseShape.skeleton(of: entry.value).map { (entry.key, $0) } }
    }
}
