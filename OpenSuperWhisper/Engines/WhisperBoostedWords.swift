import Foundation

enum WhisperBoostPreset: Sendable {
    case conservative

    var rootBoost: Float {
        switch self {
        case .conservative:
            return 1.0
        }
    }

    var continuationBoost: Float {
        switch self {
        case .conservative:
            return 2.25
        }
    }
}

struct WhisperTokenSequence: Hashable, Sendable {
    let tokens: [WhisperToken]

    var firstToken: WhisperToken? {
        tokens.first
    }
}

struct WhisperBoostTrieNode: Sendable {
    var children: [WhisperToken: WhisperBoostTrieNode] = [:]

    mutating func insert(_ tokens: ArraySlice<WhisperToken>) {
        guard let token = tokens.first else {
            return
        }

        var child = children[token] ?? WhisperBoostTrieNode()
        child.insert(tokens.dropFirst())
        children[token] = child
    }

    func node(matching tokens: ArraySlice<WhisperToken>) -> WhisperBoostTrieNode? {
        var current = self
        for token in tokens {
            guard let next = current.children[token] else {
                return nil
            }
            current = next
        }
        return current
    }
}

struct WhisperBoostedWordsModel: Sendable {
    let startVariants: [WhisperTokenSequence]
    let spacedVariants: [WhisperTokenSequence]
    let continuationTrie: WhisperBoostTrieNode
    let maxSequenceLength: Int
    let preset: WhisperBoostPreset
}

enum WhisperBoostedWordsParser {
    static func parse(_ rawValue: String) -> [String] {
        var phrases: [String] = []
        var seen: Set<String> = []

        for line in rawValue.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }

            if seen.insert(trimmed).inserted {
                phrases.append(trimmed)
            }
        }

        return phrases
    }
}

struct WhisperBoostedWordsCompiler {
    let tokenize: (String) -> [WhisperToken]

    func compile(
        rawValue: String,
        preset: WhisperBoostPreset = .conservative
    ) -> WhisperBoostedWordsModel? {
        let phrases = WhisperBoostedWordsParser.parse(rawValue)
        guard !phrases.isEmpty else {
            return nil
        }

        var startVariants: [WhisperTokenSequence] = []
        var spacedVariants: [WhisperTokenSequence] = []
        var seenStartVariants: Set<WhisperTokenSequence> = []
        var seenSpacedVariants: Set<WhisperTokenSequence> = []
        var trie = WhisperBoostTrieNode()
        var maxSequenceLength = 0

        for phrase in phrases {
            let exactVariant = WhisperTokenSequence(tokens: tokenize(phrase))
            if !exactVariant.tokens.isEmpty && seenStartVariants.insert(exactVariant).inserted {
                startVariants.append(exactVariant)
                trie.insert(ArraySlice(exactVariant.tokens))
                maxSequenceLength = max(maxSequenceLength, exactVariant.tokens.count)
            }

            let spacedVariant = WhisperTokenSequence(tokens: tokenize(" " + phrase))
            if !spacedVariant.tokens.isEmpty && seenSpacedVariants.insert(spacedVariant).inserted {
                spacedVariants.append(spacedVariant)
                trie.insert(ArraySlice(spacedVariant.tokens))
                maxSequenceLength = max(maxSequenceLength, spacedVariant.tokens.count)
            }
        }

        guard !startVariants.isEmpty || !spacedVariants.isEmpty else {
            return nil
        }

        return WhisperBoostedWordsModel(
            startVariants: startVariants,
            spacedVariants: spacedVariants,
            continuationTrie: trie,
            maxSequenceLength: maxSequenceLength,
            preset: preset
        )
    }
}

struct WhisperBoostedWordsBiaser {
    private enum RootBoundary {
        case sentenceLikeStart
        case wordBoundary
        case none
    }

    static func boosts(
        for recentTokens: [WhisperToken],
        lastTokenText: String?,
        model: WhisperBoostedWordsModel
    ) -> [WhisperToken: Float] {
        var boosts: [WhisperToken: Float] = [:]

        applyRootBoosts(
            boundary: rootBoundary(for: lastTokenText, hasRecentTokens: !recentTokens.isEmpty),
            model: model,
            boosts: &boosts
        )
        applyContinuationBoosts(
            recentTokens: recentTokens,
            model: model,
            boosts: &boosts
        )

        return boosts
    }

    private static func applyRootBoosts(
        boundary: RootBoundary,
        model: WhisperBoostedWordsModel,
        boosts: inout [WhisperToken: Float]
    ) {
        let variants: [WhisperTokenSequence]
        switch boundary {
        case .sentenceLikeStart:
            variants = model.startVariants
        case .wordBoundary:
            variants = model.spacedVariants
        case .none:
            return
        }

        for variant in variants {
            guard let token = variant.firstToken else {
                continue
            }
            boosts[token] = max(boosts[token] ?? 0, model.preset.rootBoost)
        }
    }

    private static func applyContinuationBoosts(
        recentTokens: [WhisperToken],
        model: WhisperBoostedWordsModel,
        boosts: inout [WhisperToken: Float]
    ) {
        guard model.maxSequenceLength > 1, !recentTokens.isEmpty else {
            return
        }

        let maxPrefixLength = min(recentTokens.count, model.maxSequenceLength - 1)
        guard maxPrefixLength > 0 else {
            return
        }

        for prefixLength in 1...maxPrefixLength {
            let suffix = ArraySlice(recentTokens.suffix(prefixLength))
            guard let node = model.continuationTrie.node(matching: suffix) else {
                continue
            }

            for token in node.children.keys {
                boosts[token] = max(boosts[token] ?? 0, model.preset.continuationBoost)
            }
        }
    }

    private static func rootBoundary(
        for lastTokenText: String?,
        hasRecentTokens: Bool
    ) -> RootBoundary {
        guard hasRecentTokens else {
            return .sentenceLikeStart
        }

        guard let lastTokenText, !lastTokenText.isEmpty else {
            return .sentenceLikeStart
        }

        if lastTokenText.contains(where: \.isNewline) {
            return .sentenceLikeStart
        }

        if lastTokenText.last?.isWhitespace == true {
            return .wordBoundary
        }

        let trimmed = lastTokenText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lastCharacter = trimmed.last else {
            return .wordBoundary
        }

        if isSentenceLikeBoundaryCharacter(lastCharacter) {
            return .sentenceLikeStart
        }

        return .none
    }

    private static func isSentenceLikeBoundaryCharacter(_ character: Character) -> Bool {
        if character == "'" || character == "’" || character == "-" || character == "‑" {
            return false
        }

        return character.unicodeScalars.allSatisfy {
            CharacterSet.punctuationCharacters.contains($0) || CharacterSet.symbols.contains($0)
        }
    }
}
