import Foundation

/// The `agy` program Brimline is willing to launch: one exact path, checked on the open file.
///
/// The path is `~/.local/bin/agy` and nothing else (`PATH` is never searched). The file is opened
/// without following a link (a link is refused), then checked on the open descriptor: a regular
/// file, owned by the user running Brimline, executable by its owner, not writable by the group or
/// others. Whether it is Google's program is not decided here: `AntigravityCodeChecking` checks its
/// signature. This type only answers "may Brimline even look at this file".
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

    /// What identifies the file on disk. Two reads that differ mean `agy` was replaced in between (an update).
    public struct Identity: Equatable, Sendable {
        public var device: Int32
        public var inode: UInt64
        public var size: Int64
        public var modifiedSeconds: Int
        public var modifiedNanoseconds: Int
    }

    /// The identity of the file, after the checks above. `owner` is the user id the file must belong to
    /// (the user's own).
    public static func inspect(at url: URL, owner: uid_t = getuid()) throws(Failure) -> Identity {
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

        return Identity(device: info.st_dev, inode: info.st_ino, size: info.st_size,
                        modifiedSeconds: info.st_mtimespec.tv_sec, modifiedNanoseconds: info.st_mtimespec.tv_nsec)
    }
}
