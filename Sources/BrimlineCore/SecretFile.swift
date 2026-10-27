import Foundation

/// Reads a file that holds a sign-in (a provider's `auth.json` and the like), safely.
///
/// The file is opened with `O_NOFOLLOW` (a link is refused, never followed), then checked on the
/// open descriptor with `fstat`: a regular file, owned by the user running Brimline, at most
/// `defaultMaxBytes` long. Checking the descriptor and not the path closes the gap between the
/// check and the read. Nothing is ever written, renewed or moved.
public enum SecretFile {
    /// 1 MiB: a sign-in file is a few Kio.
    public static let defaultMaxBytes = 1024 * 1024

    public enum Failure: Error, Equatable, Sendable {
        /// No file at this path.
        case notFound
        /// A link, a folder or any file that is not a regular file.
        case notRegularFile
        /// The file belongs to someone else.
        case wrongOwner
        case tooLarge
        /// The file exists but could not be read (permission, I/O).
        case unreadable
        /// The content is not the JSON expected (cut short, or another format).
        case malformed

        /// True when a new attempt can succeed: a provider tool may be rewriting its file at this
        /// very moment. The reading is then `unavailable` and tried again, never `signed_out`.
        public var isTransient: Bool { self == .malformed || self == .unreadable }
    }

    /// The bytes of the file. `owner` is the user id the file must belong to (the user's own).
    public static func read(url: URL, maxBytes: Int = defaultMaxBytes,
                            owner: uid_t = getuid()) throws(Failure) -> Data {
        // O_NONBLOCK so that a named pipe put there cannot make the open wait; it has no effect on a regular file.
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        if descriptor < 0 {
            switch errno {
            case ENOENT, ENOTDIR: throw .notFound
            case ELOOP: throw .notRegularFile
            default: throw .unreadable
            }
        }
        defer { close(descriptor) }

        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw .unreadable }
        guard (info.st_mode & S_IFMT) == S_IFREG else { throw .notRegularFile }
        guard info.st_uid == owner else { throw .wrongOwner }
        guard info.st_size <= Int64(maxBytes) else { throw .tooLarge }

        var data = Data()
        var chunk = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let count = chunk.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
            if count < 0 {
                if errno == EINTR { continue }
                throw .unreadable
            }
            if count == 0 { break }
            data.append(contentsOf: chunk[0..<count])
            // The file may have grown since fstat: the limit holds for what is really read.
            if data.count > maxBytes { throw .tooLarge }
        }
        return data
    }

    /// The file decoded as `type`. Only the fields `type` declares are decoded.
    public static func readJSON<T: Decodable>(_ type: T.Type, url: URL, maxBytes: Int = defaultMaxBytes,
                                              owner: uid_t = getuid()) throws(Failure) -> T {
        let data = try read(url: url, maxBytes: maxBytes, owner: owner)
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw .malformed
        }
    }
}
