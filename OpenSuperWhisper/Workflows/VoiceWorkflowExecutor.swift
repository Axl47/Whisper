import Foundation

struct WorkflowExecutionResult: Equatable, Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    let status: WorkflowExecutionStatus
    let message: String?
}

struct WorkflowExecutionHandle {
    let immediateResult: WorkflowExecutionResult?
    let pendingResultTask: Task<WorkflowExecutionResult, Never>?
}

enum VoiceWorkflowExecutor {
    static let payloadEnvironmentKey = "OPENSUPERWHISPER_WORKFLOW_TEXT"
    static let defaultInlineCompletionTimeoutNanoseconds: UInt64 = 400_000_000

    static func execute(workflow: VoiceWorkflow, payload: String) async -> WorkflowExecutionResult {
        await Task.detached(priority: .userInitiated) {
            run(workflow: workflow, payload: payload)
        }.value
    }

    static func start(
        workflow: VoiceWorkflow,
        payload: String,
        inlineTimeoutNanoseconds: UInt64 = defaultInlineCompletionTimeoutNanoseconds
    ) async -> WorkflowExecutionHandle {
        let executionTask = Task.detached(priority: .userInitiated) {
            run(workflow: workflow, payload: payload)
        }

        if let immediateResult = await waitForResult(
            from: executionTask,
            timeoutNanoseconds: inlineTimeoutNanoseconds
        ) {
            return WorkflowExecutionHandle(
                immediateResult: immediateResult,
                pendingResultTask: nil
            )
        }

        return WorkflowExecutionHandle(
            immediateResult: nil,
            pendingResultTask: executionTask
        )
    }

    static func substitutedArguments(arguments: [String], payload: String) -> [String] {
        arguments.map { $0.replacingOccurrences(of: "{text}", with: payload) }
    }

    static func substitutedShellCommand(command: String, payload: String) -> String {
        command.replacingOccurrences(of: "{text}", with: shellEscaped(payload))
    }

    private static func run(workflow: VoiceWorkflow, payload: String) -> WorkflowExecutionResult {
        switch workflow.launchMode {
        case .executable:
            return runExecutable(workflow: workflow, payload: payload)
        case .shell:
            return runShellCommand(workflow: workflow, payload: payload)
        }
    }

    private static func runExecutable(workflow: VoiceWorkflow, payload: String) -> WorkflowExecutionResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: workflow.executablePath)
        process.arguments = substitutedArguments(arguments: workflow.arguments, payload: payload)
        process.environment = ProcessInfo.processInfo.environment

        return runProcess(process, workflowName: workflow.name)
    }

    private static func runShellCommand(workflow: VoiceWorkflow, payload: String) -> WorkflowExecutionResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", substitutedShellCommand(command: workflow.shellCommand, payload: payload)]
        process.environment = ProcessInfo.processInfo.environment.merging(
            [payloadEnvironmentKey: payload],
            uniquingKeysWith: { _, new in new }
        )

        return runProcess(process, workflowName: workflow.name)
    }

    private static func runProcess(_ process: Process, workflowName: String) -> WorkflowExecutionResult {
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()

            let stdout = readPipe(stdoutPipe)
            let stderr = readPipe(stderrPipe)
            let exitCode = process.terminationStatus
            let status: WorkflowExecutionStatus = exitCode == 0 ? .succeeded : .failed
            let message = status == .succeeded ? nil : truncatedMessage(
                preferredMessage(from: stderr, fallback: stdout, exitCode: exitCode)
            )

            print(
                "Workflow '\(workflowName)' exited \(exitCode). stdout='\(stdout.prefix(120))' stderr='\(stderr.prefix(120))'"
            )

            return WorkflowExecutionResult(
                exitCode: exitCode,
                stdout: stdout,
                stderr: stderr,
                status: status,
                message: message
            )
        } catch {
            let message = truncatedMessage(error.localizedDescription)
            print("Workflow '\(workflowName)' failed to launch: \(message ?? error.localizedDescription)")
            return WorkflowExecutionResult(
                exitCode: -1,
                stdout: "",
                stderr: "",
                status: .failed,
                message: message
            )
        }
    }

    private static func readPipe(_ pipe: Pipe) -> String {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func preferredMessage(from stderr: String, fallback stdout: String, exitCode: Int32) -> String {
        let stderrLine = firstNonEmptyLine(in: stderr)
        if !stderrLine.isEmpty {
            return stderrLine
        }

        let stdoutLine = firstNonEmptyLine(in: stdout)
        if !stdoutLine.isEmpty {
            return stdoutLine
        }

        return "Command exited with status \(exitCode)."
    }

    private static func firstNonEmptyLine(in text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""
    }

    private static func shellEscaped(_ payload: String) -> String {
        "'" + payload.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    static func truncatedMessage(_ message: String?) -> String? {
        guard let message else {
            return nil
        }

        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if trimmed.count <= 240 {
            return trimmed
        }

        let endIndex = trimmed.index(trimmed.startIndex, offsetBy: 237)
        return String(trimmed[..<endIndex]) + "..."
    }

    private static func waitForResult(
        from task: Task<WorkflowExecutionResult, Never>,
        timeoutNanoseconds: UInt64
    ) async -> WorkflowExecutionResult? {
        await withTaskGroup(of: WorkflowExecutionResult?.self, returning: WorkflowExecutionResult?.self) { group in
            group.addTask {
                await task.value
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                return nil
            }

            let firstCompletedResult = await group.next() ?? nil
            group.cancelAll()
            return firstCompletedResult
        }
    }
}
