import Foundation

/// Reads subprocess pipe output while a process runs to avoid pipe-buffer deadlocks.
/// Never blocks with `DispatchGroup.wait()` — that can freeze the AppKit main thread.
final class PipeDrainer: @unchecked Sendable {
    private let lock = NSLock()
    private let stdoutHandle: FileHandle
    private let stderrHandle: FileHandle
    private var stdoutData = Data()
    private var stderrData = Data()

    init(stdout: Pipe, stderr: Pipe) {
        stdoutHandle = stdout.fileHandleForReading
        stderrHandle = stderr.fileHandleForReading
        startDraining(stdoutHandle) { [weak self] chunk in
            self?.append(chunk, toStdout: true)
        }
        startDraining(stderrHandle) { [weak self] chunk in
            self?.append(chunk, toStdout: false)
        }
    }

    func collect() -> (String, String) {
        stdoutHandle.readabilityHandler = nil
        stderrHandle.readabilityHandler = nil

        lock.lock()
        stdoutData.append(stdoutHandle.readDataToEndOfFile())
        stderrData.append(stderrHandle.readDataToEndOfFile())
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        lock.unlock()
        return (stdout, stderr)
    }

    private func append(_ chunk: Data, toStdout: Bool) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        if toStdout {
            stdoutData.append(chunk)
        } else {
            stderrData.append(chunk)
        }
        lock.unlock()
    }

    private func startDraining(_ handle: FileHandle, onChunk: @escaping @Sendable (Data) -> Void) {
        handle.readabilityHandler = { fileHandle in
            let data = fileHandle.availableData
            if !data.isEmpty {
                onChunk(data)
            }
        }
    }
}
