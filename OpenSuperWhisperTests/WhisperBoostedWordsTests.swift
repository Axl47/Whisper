import XCTest
@testable import OpenSuperWhisper

final class WhisperBoostedWordsTests: XCTestCase {
    private func makeCompiler(
        tokenMap: [String: [WhisperToken]]
    ) -> WhisperBoostedWordsCompiler {
        WhisperBoostedWordsCompiler { text in
            tokenMap[text] ?? []
        }
    }

    func testParser_trimsBlankLinesAndDedupesExactDuplicates() {
        let parsed = WhisperBoostedWordsParser.parse(
            """

              Kubernetes
            Grafana
            Kubernetes
             Prometheus

            """
        )

        XCTAssertEqual(parsed, ["Kubernetes", "Grafana", "Prometheus"])
    }

    func testCompiler_emitsExactAndLeadingSpaceVariants() {
        let compiler = makeCompiler(
            tokenMap: [
                "Kubernetes": [11, 12],
                " Kubernetes": [21, 22],
                "Grafana": [31],
                " Grafana": [41],
            ]
        )

        let model = compiler.compile(
            rawValue: "Kubernetes\nGrafana",
            preset: .conservative
        )

        XCTAssertEqual(model?.startVariants.map(\.tokens), [[11, 12], [31]])
        XCTAssertEqual(model?.spacedVariants.map(\.tokens), [[21, 22], [41]])
        XCTAssertEqual(model?.maxSequenceLength, 2)
    }

    func testBiaser_appliesRootBoostsOnlyAtValidBoundaries() {
        let compiler = makeCompiler(
            tokenMap: [
                "Kubernetes": [11, 12],
                " Kubernetes": [21, 22],
            ]
        )
        let model = compiler.compile(rawValue: "Kubernetes", preset: .conservative)!

        let sentenceStartBoosts = WhisperBoostedWordsBiaser.boosts(
            for: [],
            lastTokenText: nil,
            model: model
        )
        XCTAssertEqual(sentenceStartBoosts[11], 1.0)
        XCTAssertNil(sentenceStartBoosts[21])

        let wordBoundaryBoosts = WhisperBoostedWordsBiaser.boosts(
            for: [999],
            lastTokenText: " ",
            model: model
        )
        XCTAssertEqual(wordBoundaryBoosts[21], 1.0)
        XCTAssertNil(wordBoundaryBoosts[11])

        let midWordBoosts = WhisperBoostedWordsBiaser.boosts(
            for: [999],
            lastTokenText: "hello",
            model: model
        )
        XCTAssertTrue(midWordBoosts.isEmpty)
    }

    func testBiaser_appliesContinuationBoostWhenPrefixMatches() {
        let compiler = makeCompiler(
            tokenMap: [
                "Kubernetes": [11, 12, 13],
                " Kubernetes": [21, 22, 23],
            ]
        )
        let model = compiler.compile(rawValue: "Kubernetes", preset: .conservative)!

        let boosts = WhisperBoostedWordsBiaser.boosts(
            for: [11],
            lastTokenText: "Kube",
            model: model
        )

        XCTAssertEqual(boosts[12], 2.25)
        XCTAssertNil(boosts[11])
    }

    func testBiaser_usesMaximumBoostInsteadOfSummingDuplicates() {
        let compiler = makeCompiler(
            tokenMap: [
                "Alpha": [50],
                " Alpha": [60],
                "Beta": [50],
                " Beta": [70],
            ]
        )
        let model = compiler.compile(rawValue: "Alpha\nBeta", preset: .conservative)!

        let boosts = WhisperBoostedWordsBiaser.boosts(
            for: [],
            lastTokenText: nil,
            model: model
        )

        XCTAssertEqual(boosts[50], 1.0)
        XCTAssertEqual(boosts.count, 1)
    }

    func testCompiler_returnsNilForEmptyGlossary() {
        let compiler = makeCompiler(tokenMap: [:])
        XCTAssertNil(compiler.compile(rawValue: "", preset: .conservative))
        XCTAssertNil(compiler.compile(rawValue: " \n \n", preset: .conservative))
    }

    func testAppPreferences_whisperBoostedWordsRoundTrip() {
        let preferences = AppPreferences.shared
        let originalValue = preferences.whisperBoostedWords

        defer {
            preferences.whisperBoostedWords = originalValue
        }

        let boostedWords = "Kubernetes\nGrafana"
        preferences.whisperBoostedWords = boostedWords

        XCTAssertEqual(preferences.whisperBoostedWords, boostedWords)
    }
}
