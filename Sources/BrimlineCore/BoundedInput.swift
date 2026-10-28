import Foundation

/// Reads a command's standard input in blocks, with bounds, and always to its end.
///
/// A command at the end of a pipe (`claude -p ... | brimline report claude ...`) must read everything the
/// program before it writes: if it leaves early, that program's next write fails (`EPIPE`, or `SIGPIPE`) and a
/// script that runs it with `set -o pipefail` sees a failure. So every path reads to the end, even a usage error,
/// and what goes past a bound is read and dropped, never kept in memory.
public enum BoundedInput {
    static let blockSize = 64 * 1024

    /// Calls `body` with each line (without its `\n` or `\r\n`), in order, until the end of the input. A line
    /// longer than `maxLineBytes` is dropped whole, and its bytes are never held beyond `maxLineBytes`.
    public static func forEachLine(descriptor: Int32, maxLineBytes: Int, _ body: (Data) -> Void) {
        var pending = Data()
        // True while the bytes read belong to a line already too long: they are dropped up to its end.
        var dropping = false
        func emit(_ line: Data) {
            var line = line
            if line.last == UInt8(ascii: "\r") { line.removeLast() }
            if line.count <= maxLineBytes { body(line) }
        }
        _ = readBlocks(descriptor) { block in
            var start = block.startIndex
            while start < block.endIndex {
                guard let newline = block[start...].firstIndex(of: UInt8(ascii: "\n")) else {
                    if !dropping {
                        pending.append(block[start...])
                        // `\r` may still come before the newline: one byte of slack.
                        if pending.count > maxLineBytes + 1 { pending.removeAll(keepingCapacity: false); dropping = true }
                    }
                    break
                }
                if dropping {
                    dropping = false
                } else {
                    pending.append(block[start..<newline])
                    emit(pending)
                }
                pending.removeAll(keepingCapacity: true)
                start = block.index(after: newline)
            }
        }
        if !dropping, !pending.isEmpty { emit(pending) }
    }

    /// The whole input when it is `limit` bytes or less; nil past it (the rest is still read, and dropped) or
    /// when it cannot be read.
    public static func readAll(descriptor: Int32, limit: Int) -> Data? {
        var data = Data()
        var tooLong = false
        let ok = readBlocks(descriptor) { block in
            guard !tooLong else { return }
            data.append(block)
            if data.count > limit { tooLong = true; data = Data() }
        }
        return ok && !tooLong ? data : nil
    }

    /// Reads the input to its end and drops it, except from a terminal (nobody is writing: waiting would hang).
    public static func drain(descriptor: Int32) {
        guard isatty(descriptor) == 0 else { return }
        _ = readBlocks(descriptor) { _ in }
    }

    /// Reads blocks until the end; false when a read fails (other than an interruption, or nothing to read yet).
    private static func readBlocks(_ descriptor: Int32, _ body: (Data) -> Void) -> Bool {
        var chunk = [UInt8](repeating: 0, count: blockSize)
        while true {
            let count = chunk.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
            if count < 0 {
                if errno == EINTR { continue }
                // An input the program before left non-blocking (`O_NONBLOCK` belongs to the open file, shared with
                // it) says "nothing yet" while that program has not written: wait for data or for the end, never
                // take it for a failure. The flag is not changed: it is the other program's too.
                if errno == EAGAIN || errno == EWOULDBLOCK, waitForInput(descriptor) { continue }
                return false
            }
            if count == 0 { return true }
            body(Data(chunk[0..<count]))
        }
    }

    /// Waits, as a blocking read would, until the descriptor has data, its end or an error; false when it
    /// cannot be waited on.
    private static func waitForInput(_ descriptor: Int32) -> Bool {
        var request = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
        while true {
            let ready = poll(&request, 1, -1)
            if ready < 0 && errno == EINTR { continue }
            return ready > 0 && (Int32(request.revents) & POLLNVAL) == 0
        }
    }
}
