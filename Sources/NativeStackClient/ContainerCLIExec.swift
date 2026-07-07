import Darwin
import Foundation
import NativeStackCore

enum ContainerCLIExec {
    private static let interactiveShells: Set<String> = ["sh", "bash", "zsh", "ash", "dash", "fish"]

    static func shouldRunInteractively(
        command: [String],
        interactive: Bool,
        tty: Bool,
        detach: Bool
    ) -> Bool {
        if detach { return false }
        if interactive || tty { return true }
        guard isStandardInputTTY(), let first = command.first else { return false }

        let shell = (first as NSString).lastPathComponent
        guard interactiveShells.contains(shell) else { return false }
        if command.contains("-c") { return false }
        return true
    }

    static func isStandardInputTTY() -> Bool {
        isatty(STDIN_FILENO) == 1
    }

    static func exec(
        arguments: [String],
        config: ContainerCLIConfiguration = ContainerCLIConfiguration()
    ) throws -> Never {
        guard let path = config.resolvedInstalledPath() else {
            throw NativeStackError.containerCLINotFound
        }

        var argv: [UnsafeMutablePointer<CChar>?] = [strdup(path)]
        defer { argv.forEach { if let pointer = $0 { free(pointer) } } }

        for argument in arguments {
            argv.append(strdup(argument))
        }
        argv.append(nil)

        _ = argv.withUnsafeMutableBufferPointer { buffer in
            execv(path, buffer.baseAddress)
        }

        throw NativeStackError.commandFailed(
            command: ([path] + arguments).joined(separator: " "),
            exitCode: errno,
            output: String(cString: strerror(errno))
        )
    }
}
