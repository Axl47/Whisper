import Foundation

struct WorkflowMatch: Equatable {
    let workflow: VoiceWorkflow
    let payload: String
}

struct VoiceWorkflowMatcher {
    private static let timestampRegex = try? NSRegularExpression(
        pattern: #"(?m)^\s*\[\d+(?:\.\d+)?->\d+(?:\.\d+)?\]\s*"#
    )
    private static let whitespaceRegex = try? NSRegularExpression(pattern: #"\s+"#)
    private static let payloadSeparatorCharacterSet = CharacterSet(charactersIn: " \t,;:-–—")

    static func match(
        transcript: String,
        workflows: [VoiceWorkflow],
        isEnabled: Bool
    ) -> WorkflowMatch? {
        guard isEnabled else {
            return nil
        }

        let enabledWorkflows = workflows.filter(\.isEnabled)
        guard !enabledWorkflows.isEmpty else {
            return nil
        }

        let cleanedTranscript = cleanedTranscriptPreservingCase(from: transcript)
        guard !cleanedTranscript.isEmpty else {
            return nil
        }

        let candidates = enabledWorkflows.flatMap { workflow in
            workflow.aliases.compactMap { alias -> (workflow: VoiceWorkflow, alias: String, payload: String)? in
                let normalizedAlias = VoiceWorkflowValidator.normalizedAlias(alias)
                guard !normalizedAlias.isEmpty else {
                    return nil
                }
                guard let matchedRange = matchedAliasRange(
                    normalizedAlias: normalizedAlias,
                    in: cleanedTranscript
                ) else {
                    return nil
                }

                let remainder = cleanedTranscript[matchedRange.upperBound...]
                let payload = trimPayloadSeparators(from: String(remainder))
                return (workflow, normalizedAlias, payload)
            }
        }

        guard let bestMatch = candidates.max(by: { lhs, rhs in
            lhs.alias.count < rhs.alias.count
        }) else {
            return nil
        }

        return WorkflowMatch(workflow: bestMatch.workflow, payload: bestMatch.payload)
    }

    static func cleanedTranscriptPreservingCase(from transcript: String) -> String {
        var cleaned = transcript

        if let timestampRegex {
            let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
            cleaned = timestampRegex.stringByReplacingMatches(
                in: cleaned,
                range: range,
                withTemplate: ""
            )
        }

        cleaned = cleaned.replacingOccurrences(of: "\n", with: " ")

        if let whitespaceRegex {
            let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
            cleaned = whitespaceRegex.stringByReplacingMatches(
                in: cleaned,
                range: range,
                withTemplate: " "
            )
        }

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func matchedAliasRange(
        normalizedAlias: String,
        in transcript: String
    ) -> Range<String.Index>? {
        guard !normalizedAlias.isEmpty else {
            return nil
        }

        let aliasComponents = normalizedAlias.split(separator: " ").map(String.init)
        guard !aliasComponents.isEmpty else {
            return nil
        }

        let aliasPattern = aliasComponents
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: #"\s+"#)
        let pattern = #"^\s*[\p{P}]*\s*(\#(aliasPattern))(?=$|[\s\p{P}])"#

        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else {
            return nil
        }

        let searchRange = NSRange(transcript.startIndex..<transcript.endIndex, in: transcript)
        guard let match = regex.firstMatch(in: transcript, range: searchRange),
              let aliasRange = Range(match.range(at: 1), in: transcript) else {
            return nil
        }

        return aliasRange
    }

    private static func trimPayloadSeparators(from payload: String) -> String {
        payload.trimmingCharacters(in: payloadSeparatorCharacterSet)
    }
}
