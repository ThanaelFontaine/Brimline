import CryptoKit
import Foundation

/// The `agy` program Brimline is willing to launch: one exact path, checked on the open file.
///
/// The path is `~/.local/bin/agy` and nothing else (`PATH` is never searched). The file is opened
/// without following a link (a link is refused), then checked on the open descriptor: a regular
/// file, owned by the user running Brimline, executable by its owner, not writable by the group or
/// others. Its SHA-256 is computed from that same descriptor, so what is checked is what is hashed.
public enum AntigravityBinary {
    /// Where the installer of Antigravity puts `agy`, from the user's home folder.
    public static let relativePath = ".local/bin/agy"

    public enum Failure: Error, Equatable, Sendable {
        /// Nothing at this path.
        case notFound
        /// A link, a folder, a file of someone else, a file anyone can write, or one that is not executable.
        case refused
        case unreadable
    }

    public static func url(home: URL) -> URL {
        home.appendingPathComponent(relativePath)
    }

    /// Whether something is at the path (a link counts: it is refused later, not ignored). One `lstat`.
    public static func isPresent(at url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0
    }

    /// The SHA-256 (lowercase hex) of the binary, after the checks above. `owner` is the user id the
    /// file must belong to (the user's own).
    public static func inspect(at url: URL, owner: uid_t = getuid()) throws(Failure) -> String {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        if descriptor < 0 {
            switch errno {
            case ENOENT, ENOTDIR: throw .notFound
            case ELOOP: throw .refused
            default: throw .unreadable
            }
        }
        defer { close(descriptor) }

        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw .unreadable }
        guard (info.st_mode & S_IFMT) == S_IFREG, info.st_uid == owner,
              (info.st_mode & S_IXUSR) != 0, (info.st_mode & (S_IWGRP | S_IWOTH)) == 0 else { throw .refused }

        var hasher = SHA256()
        var chunk = [UInt8](repeating: 0, count: 1024 * 1024)
        while true {
            let count = chunk.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
            if count < 0 {
                if errno == EINTR { continue }
                throw .unreadable
            }
            if count == 0 { break }
            hasher.update(data: chunk[0..<count])
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
