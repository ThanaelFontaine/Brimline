import Foundation

/// Brimline was called Sightglass. At the first launch, the settings and the usage cache of the old
/// folder (`~/Library/Application Support/Sightglass/`) are copied into the new one, so that the
/// accounts, labels and choices of the user come along.
///
/// It is a copy of two files, never of the folder, and it is careful on purpose:
/// - the old folder must be a real folder owned by the user, never a link;
/// - each source is opened without following a link, must be a regular file owned by the user of
///   1 MiB at most, and is decoded into its own type then encoded again (so only what these types
///   hold goes over, and a file that does not decode is left behind);
/// - a file already present in the new folder is never replaced, which also settles the race
///   between the app and the command starting together;
/// - the old folder is never changed or removed;
/// - the marker is written last, only when everything went through: a half done migration
///   completes at the next launch.
public enum LegacyMigration {
    public static let markerName = ".migrated-from-sightglass"
    static let legacyFolderName = "Sightglass"
    static let maximumSize = 1 << 20

    public struct Outcome: Equatable, Sendable {
        /// The files copied by this call.
        public var copied: [String] = []
        /// The marker is there at the end (it was, or this call wrote it).
        public var done = false
    }

    typealias Writer = (Data, URL) throws -> Void

    /// Runs the migration. Idempotent and silent: a failure never stops the launch.
    @discardableResult
    public static func run(paths: BrimlinePaths = BrimlinePaths()) -> Outcome {
        run(paths: paths, write: { data, url in try JSONCoding.write(data, to: url, replacing: false) })
    }

    static func run(paths: BrimlinePaths, write: Writer) -> Outcome {
        var outcome = Outcome()
        let marker = paths.supportDirectory.appendingPathComponent(markerName)
        if exists(marker) {
            outcome.done = true
            return outcome
        }

        let legacy = paths.home.appendingPathComponent("Library/Application Support/\(legacyFolderName)", isDirectory: true)
        var status = stat()
        if lstat(legacy.path, &status) != 0 {
            guard errno == ENOENT else { return outcome }
            outcome.done = place(marker, write: write)
            return outcome
        }
        guard status.st_mode & S_IFMT == S_IFDIR, status.st_uid == getuid() else { return outcome }

        var complete = true
        let files: [(String, (Data) -> Data?)] = [
            ("settings.json", { reencode($0, as: BrimlineSettings.self) }),
            ("usage.json", { reencode($0, as: UsageSnapshot.self) }),
        ]
        for (name, convert) in files {
            guard let data = readOwnedFile(legacy.appendingPathComponent(name)),
                  let converted = convert(data) else { continue }
            let destination = paths.supportDirectory.appendingPathComponent(name)
            if exists(destination) { continue }
            do {
                try write(converted, destination)
                outcome.copied.append(name)
            } catch let error as POSIXError where error.code == .EEXIST {
                continue
            } catch {
                complete = false
            }
        }
        if complete { outcome.done = place(marker, write: write) }
        return outcome
    }

    private static func place(_ marker: URL, write: Writer) -> Bool {
        do {
            try write(Data("migrated from Sightglass\n".utf8), marker)
            return true
        } catch let error as POSIXError where error.code == .EEXIST {
            return true
        } catch {
            return false
        }
    }

    private static func exists(_ url: URL) -> Bool {
        var status = stat()
        return lstat(url.path, &status) == 0
    }

    private static func reencode<T: Codable>(_ data: Data, as type: T.Type) -> Data? {
        guard let value = try? JSONCoding.decoder().decode(type, from: data) else { return nil }
        return try? JSONCoding.encoder().encode(value)
    }

    /// The content of a regular file owned by the user, opened without following a link, at most 1 MiB.
    private static func readOwnedFile(_ url: URL) -> Data? {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var status = stat()
        guard fstat(descriptor, &status) == 0,
              status.st_mode & S_IFMT == S_IFREG,
              status.st_uid == getuid(),
              status.st_size <= off_t(maximumSize) else { return nil }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = read(descriptor, &buffer, buffer.count)
            if count < 0 {
                if errno == EINTR { continue }
                return nil
            }
            if count == 0 { break }
            data.append(buffer, count: count)
            if data.count > maximumSize { return nil }
        }
        return data
    }
}
