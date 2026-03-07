import Foundation

enum VoiceWorkflowValidationError: Equatable, Hashable, LocalizedError {
    case missingName
    case missingAlias
    case duplicateAlias(String)
    case executablePathMustBeAbsolute
    case executablePathDoesNotExist
    case executablePathIsNotExecutable
    case missingTextPlaceholder
    case missingShellCommand
    case missingShellPayloadReference

    var errorDescription: String? {
        switch self {
        case .missingName:
            return "Name is required."
        case .missingAlias:
            return "At least one alias is required."
        case let .duplicateAlias(alias):
            return "Alias '\(alias)' is already used by another workflow."
        case .executablePathMustBeAbsolute:
            return "Executable path must be absolute."
        case .executablePathDoesNotExist:
            return "Executable path does not exist."
        case .executablePathIsNotExecutable:
            return "Executable path is not executable."
        case .missingTextPlaceholder:
            return "At least one argument must contain {text}."
        case .missingShellCommand:
            return "Shell command is required."
        case .missingShellPayloadReference:
            return "Shell command must contain {text} or $" + VoiceWorkflowExecutor.payloadEnvironmentKey + "."
        }
    }
}

struct VoiceWorkflowValidator {
    private static let collapsedWhitespaceRegex = try? NSRegularExpression(pattern: #"[\s\n]+"#)

    static func validate(
        workflow: VoiceWorkflow,
        duringSaveAgainst existing: [VoiceWorkflow]
    ) -> [VoiceWorkflowValidationError] {
        var errors: [VoiceWorkflowValidationError] = []

        if workflow.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append(.missingName)
        }

        let normalizedAliases = workflow.aliases
            .map(normalizedAlias(_:))
            .filter { !$0.isEmpty }

        if normalizedAliases.isEmpty {
            errors.append(.missingAlias)
        }

        var seenAliases = Set<String>()
        for alias in normalizedAliases {
            if !seenAliases.insert(alias).inserted {
                errors.append(.duplicateAlias(alias))
            }
        }

        let otherAliases = existing
            .filter { $0.id != workflow.id }
            .flatMap(\.aliases)
            .map(normalizedAlias(_:))
            .filter { !$0.isEmpty }

        let otherAliasSet = Set(otherAliases)
        for alias in seenAliases where otherAliasSet.contains(alias) {
            errors.append(.duplicateAlias(alias))
        }

        switch workflow.launchMode {
        case .executable:
            let executablePath = workflow.executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
            if !executablePath.isEmpty {
                if !executablePath.hasPrefix("/") {
                    errors.append(.executablePathMustBeAbsolute)
                } else {
                    var isDirectory: ObjCBool = false
                    let exists = FileManager.default.fileExists(atPath: executablePath, isDirectory: &isDirectory)
                    if !exists || isDirectory.boolValue {
                        errors.append(.executablePathDoesNotExist)
                    } else if !FileManager.default.isExecutableFile(atPath: executablePath) {
                        errors.append(.executablePathIsNotExecutable)
                    }
                }
            } else {
                errors.append(.executablePathDoesNotExist)
            }

            if !workflow.arguments.contains(where: { $0.contains("{text}") }) {
                errors.append(.missingTextPlaceholder)
            }
        case .shell:
            let shellCommand = workflow.shellCommand.trimmingCharacters(in: .whitespacesAndNewlines)
            if shellCommand.isEmpty {
                errors.append(.missingShellCommand)
            } else if !shellCommand.contains("{text}")
                && !shellCommand.contains("$" + VoiceWorkflowExecutor.payloadEnvironmentKey)
                && !shellCommand.contains("${" + VoiceWorkflowExecutor.payloadEnvironmentKey + "}") {
                errors.append(.missingShellPayloadReference)
            }
        }

        var uniqueErrors: [VoiceWorkflowValidationError] = []
        var seenErrors = Set<VoiceWorkflowValidationError>()
        for error in errors where seenErrors.insert(error).inserted {
            uniqueErrors.append(error)
        }
        return uniqueErrors
    }

    static func normalizedAlias(_ alias: String) -> String {
        let whitespaceCollapsed: String
        if let collapsedWhitespaceRegex {
            let range = NSRange(alias.startIndex..<alias.endIndex, in: alias)
            whitespaceCollapsed = collapsedWhitespaceRegex.stringByReplacingMatches(
                in: alias,
                range: range,
                withTemplate: " "
            )
        } else {
            whitespaceCollapsed = alias.replacingOccurrences(of: "\n", with: " ")
        }

        let punctuation = CharacterSet.punctuationCharacters
        return whitespaceCollapsed
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: punctuation)
            .lowercased()
    }
}
