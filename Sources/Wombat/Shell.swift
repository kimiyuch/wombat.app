import Foundation
import AppKit

/// Small helpers for running command-line tools off the main thread.
enum Shell {
    struct Result {
        let status: Int32
        let out: String
    }

    static func run(_ launchPath: String, _ args: [String], mergeStderr: Bool = false) async -> Result {
        await withCheckedContinuation { (cont: CheckedContinuation<Result, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: launchPath)
                process.arguments = args
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = mergeStderr ? pipe : FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    cont.resume(returning: Result(status: -1, out: error.localizedDescription))
                    return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                cont.resume(returning: Result(status: process.terminationStatus, out: String(decoding: data, as: UTF8.self)))
            }
        }
    }

    /// Runs a command the way your Terminal would find it (Homebrew, nvm, Docker on PATH).
    static func login(_ command: String) async -> Result {
        let script = """
        export PATH="/opt/homebrew/bin:/usr/local/bin:/Applications/Docker.app/Contents/Resources/bin:$PATH"
        [ -s "$HOME/.nvm/nvm.sh" ] && . "$HOME/.nvm/nvm.sh" >/dev/null 2>&1
        \(command)
        """
        return await run("/bin/zsh", ["-lc", script], mergeStderr: true)
    }

    /// Sizes in bytes for many paths, using `du -sk` in parallel batches.
    static func sizes(_ paths: [String]) async -> [String: Int64] {
        guard !paths.isEmpty else { return [:] }
        let batch = 100
        let chunks = stride(from: 0, to: paths.count, by: batch).map {
            Array(paths[$0..<min($0 + batch, paths.count)])
        }
        return await withTaskGroup(of: [String: Int64].self) { group in
            for chunk in chunks {
                group.addTask { await du(chunk) }
            }
            var all: [String: Int64] = [:]
            for await part in group {
                all.merge(part) { first, _ in first }
            }
            return all
        }
    }

    private static func du(_ paths: [String]) async -> [String: Int64] {
        let result = await run("/usr/bin/du", ["-sk"] + paths)
        var out: [String: Int64] = [:]
        for line in result.out.split(separator: "\n") {
            guard let tab = line.firstIndex(of: "\t"),
                  let kb = Int64(line[..<tab].trimmingCharacters(in: .whitespaces)) else { continue }
            out[String(line[line.index(after: tab)...])] = kb * 1024
        }
        return out
    }
}

/// Runs blocking file work on a background queue.
func onBackground(_ work: @escaping () throws -> Void) async throws {
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try work()
                cont.resume()
            } catch {
                cont.resume(throwing: error)
            }
        }
    }
}

private let byteFormatter: ByteCountFormatter = {
    let f = ByteCountFormatter()
    f.countStyle = .file
    f.allowedUnits = [.useTB, .useGB, .useMB, .useKB]
    return f
}()

func fmt(_ bytes: Int64) -> String {
    byteFormatter.string(fromByteCount: bytes)
}

func reveal(_ path: String) {
    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
}
