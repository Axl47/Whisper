import AVFoundation
import Foundation

private final class UnsafeSendableBox<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}

struct LiveTranscriptionUpdate: Sendable, Equatable {
    let committedText: String
    let committedDelta: String
    let previewTail: String
    let committedEndTime: Double
    let isFinal: Bool

    static let empty = LiveTranscriptionUpdate(
        committedText: "",
        committedDelta: "",
        previewTail: "",
        committedEndTime: 0,
        isFinal: false
    )
}

private struct LiveWhisperSessionConfiguration {
    static let sampleRate = 16_000.0
    static let minimumWarmupSeconds = 2.0
    static let decodeCadenceSeconds = 1.5
    static let maxWindowSeconds = 12.0
    static let overlapSeconds = 2.0
    static let stabilityBufferSeconds = 1.5
    static let retainedBufferSeconds = 18.0

    let minimumWarmupSamples = Int(minimumWarmupSeconds * sampleRate)
    let decodeCadenceSamples = Int(decodeCadenceSeconds * sampleRate)
    let maxWindowSamples = Int(maxWindowSeconds * sampleRate)
    let retainedBufferSamples = Int(retainedBufferSeconds * sampleRate)
}

private struct DecodeSnapshot: Sendable {
    let samples: [Float]
    let startTime: Double
    let liveEdge: Double
    let isFinal: Bool
}

struct LiveTranscriptionAccumulator {
    private static let whisperControlTokenPattern = #"\[_[A-Z0-9]+(?:_[A-Z0-9]+)*_?\]"#
    private static let knownHallucinationPhrases = [
        "ask for follow-up changes",
        "ask for follow up changes",
    ]

    private struct WordToken {
        let normalized: String
        let range: Range<String.Index>
    }

    private struct TimedTextUnit {
        let text: String
        let startTime: Double
        let endTime: Double
    }

    private(set) var committedText = ""
    private(set) var previewTail = ""
    private(set) var lastCommittedEndTime = 0.0

    private let addSpaceAfterSentence: Bool

    init(addSpaceAfterSentence: Bool) {
        self.addSpaceAfterSentence = addSpaceAfterSentence
    }

    mutating func apply(
        segments: [WhisperSegmentResult],
        liveEdge: Double,
        isFinal: Bool,
        stabilityBufferSeconds: Double = LiveWhisperSessionConfiguration.stabilityBufferSeconds
    ) -> LiveTranscriptionUpdate {
        let commitHorizon = isFinal ? liveEdge : max(0, liveEdge - stabilityBufferSeconds)
        let relevantSegments = segments
            .sorted { lhs, rhs in
                if lhs.startTime == rhs.startTime {
                    return lhs.endTime < rhs.endTime
                }
                return lhs.startTime < rhs.startTime
            }
            .filter { $0.endTime > lastCommittedEndTime }

        if segments.contains(where: { !$0.tokens.isEmpty }) {
            return applyTokenBoundaries(
                segments: relevantSegments,
                commitHorizon: commitHorizon,
                isFinal: isFinal
            )
        }

        return applySegmentBoundaries(
            segments: relevantSegments,
            commitHorizon: commitHorizon,
            isFinal: isFinal
        )
    }

    private mutating func applyTokenBoundaries(
        segments: [WhisperSegmentResult],
        commitHorizon: Double,
        isFinal: Bool
    ) -> LiveTranscriptionUpdate {
        let relevantTokens = segments
            .flatMap(\.tokens)
            .map {
                TimedTextUnit(
                    text: $0.text,
                    startTime: $0.startTime,
                    endTime: $0.endTime
                )
            }
            .sorted { lhs, rhs in
                if lhs.startTime == rhs.startTime {
                    if lhs.endTime == rhs.endTime {
                        return lhs.text < rhs.text
                    }
                    return lhs.endTime < rhs.endTime
                }
                return lhs.startTime < rhs.startTime
            }
            .filter {
                !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                $0.endTime > lastCommittedEndTime
            }

        var committedTokens: [TimedTextUnit] = []
        var previewTokens: [TimedTextUnit] = []
        var updatedCommittedEndTime = lastCommittedEndTime

        for token in relevantTokens {
            if token.endTime <= commitHorizon {
                committedTokens.append(token)
                updatedCommittedEndTime = max(updatedCommittedEndTime, token.endTime)
            } else {
                previewTokens.append(token)
            }
        }

        return buildUpdate(
            committedTextRaw: Self.joinTokenTexts(committedTokens),
            previewTextRaw: Self.joinTokenTexts(previewTokens),
            updatedCommittedEndTime: updatedCommittedEndTime,
            isFinal: isFinal
        )
    }

    private mutating func applySegmentBoundaries(
        segments: [WhisperSegmentResult],
        commitHorizon: Double,
        isFinal: Bool
    ) -> LiveTranscriptionUpdate {
        var committedSegments: [String] = []
        var previewSegments: [String] = []
        var updatedCommittedEndTime = lastCommittedEndTime

        for segment in segments {
            if segment.endTime <= commitHorizon {
                committedSegments.append(segment.text)
                updatedCommittedEndTime = max(updatedCommittedEndTime, segment.endTime)
            } else {
                previewSegments.append(segment.text)
            }
        }

        return buildUpdate(
            committedTextRaw: Self.joinSegmentTexts(committedSegments),
            previewTextRaw: Self.joinSegmentTexts(previewSegments),
            updatedCommittedEndTime: updatedCommittedEndTime,
            isFinal: isFinal
        )
    }

    private mutating func buildUpdate(
        committedTextRaw: String,
        previewTextRaw: String,
        updatedCommittedEndTime: Double,
        isFinal: Bool
    ) -> LiveTranscriptionUpdate {
        let sanitizedCommittedText = Self.sanitizeStreamingArtifacts(in: committedTextRaw)
        let sanitizedPreviewText = Self.sanitizeStreamingArtifacts(in: previewTextRaw)
        let rawCommittedDelta = Self.removeTextualOverlap(
            existingText: committedText,
            incomingText: sanitizedCommittedText
        )
        let committedDelta = Self.prepareCommittedDelta(
            rawCommittedDelta,
            existingText: committedText,
            addSpaceAfterSentence: addSpaceAfterSentence
        )

        if !committedDelta.isEmpty {
            committedText += committedDelta
        }

        lastCommittedEndTime = updatedCommittedEndTime
        previewTail = Self.preparePreviewTail(
            Self.removeTextualOverlap(
                existingText: committedText,
                incomingText: sanitizedPreviewText
            ),
            existingText: committedText
        )

        return LiveTranscriptionUpdate(
            committedText: committedText,
            committedDelta: committedDelta,
            previewTail: previewTail,
            committedEndTime: lastCommittedEndTime,
            isFinal: isFinal
        )
    }

    private static func joinSegmentTexts(_ texts: [String]) -> String {
        texts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func joinTokenTexts(_ tokens: [TimedTextUnit]) -> String {
        tokens.map(\.text).joined()
    }

    private static func sanitizeStreamingArtifacts(in text: String) -> String {
        guard !text.isEmpty else {
            return text
        }

        var cleaned = text.replacingOccurrences(
            of: whisperControlTokenPattern,
            with: "",
            options: .regularExpression
        )

        for phrase in knownHallucinationPhrases {
            while let range = cleaned.range(of: phrase, options: [.caseInsensitive]) {
                cleaned.removeSubrange(range)
            }
        }

        cleaned = cleaned.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return cleaned
    }

    private static func prepareCommittedDelta(
        _ text: String,
        existingText: String,
        addSpaceAfterSentence: Bool
    ) -> String {
        var prepared = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prepared.isEmpty else {
            return ""
        }

        if shouldInsertLeadingSpace(existingText: existingText, incomingText: prepared) {
            prepared = " " + prepared
        }

        if addSpaceAfterSentence,
           let lastCharacter = prepared.last,
           lastCharacter.isPunctuation,
           !lastCharacter.isWhitespace
        {
            prepared += " "
        }

        return prepared
    }

    private static func preparePreviewTail(_ text: String, existingText: String) -> String {
        var prepared = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prepared.isEmpty else {
            return ""
        }

        if shouldInsertLeadingSpace(existingText: existingText, incomingText: prepared) {
            prepared = " " + prepared
        }

        return prepared
    }

    private static func shouldInsertLeadingSpace(existingText: String, incomingText: String) -> Bool {
        guard !existingText.isEmpty,
              let lastCharacter = existingText.last,
              let firstIncomingCharacter = incomingText.first
        else {
            return false
        }

        if lastCharacter.isWhitespace || firstIncomingCharacter.isWhitespace {
            return false
        }

        if firstIncomingCharacter.isPunctuation {
            return false
        }

        return true
    }

    private static func removeTextualOverlap(existingText: String, incomingText: String) -> String {
        let trimmedIncoming = incomingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedIncoming.isEmpty, !existingText.isEmpty else {
            return trimmedIncoming
        }

        let existingTokens = wordTokens(in: existingText)
        let incomingTokens = wordTokens(in: trimmedIncoming)
        guard existingTokens.count >= 2, incomingTokens.count >= 2 else {
            return trimmedIncoming
        }

        let maxOverlap = min(existingTokens.count, incomingTokens.count)
        for overlapCount in stride(from: maxOverlap, through: 2, by: -1) {
            let existingSuffix = existingTokens.suffix(overlapCount).map(\.normalized)
            let incomingPrefix = incomingTokens.prefix(overlapCount).map(\.normalized)
            guard existingSuffix.elementsEqual(incomingPrefix) else {
                continue
            }

            let boundaryIndex = incomingTokens[overlapCount - 1].range.upperBound
            let remainder = String(trimmedIncoming[boundaryIndex...])
            return trimSharedBoundaryCharacters(existingText: existingText, incomingRemainder: remainder)
        }

        return trimmedIncoming
    }

    private static func wordTokens(in text: String) -> [WordToken] {
        var tokens: [WordToken] = []
        var tokenStart: String.Index?
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            if isWordCharacter(character) {
                if tokenStart == nil {
                    tokenStart = index
                }
            } else if let tokenStartIndex = tokenStart {
                let range = tokenStartIndex..<index
                let token = text[range].lowercased()
                if !token.isEmpty {
                    tokens.append(WordToken(normalized: token, range: range))
                }
                tokenStart = nil
            }

            index = text.index(after: index)
        }

        if let tokenStart {
            let range = tokenStart..<text.endIndex
            let token = text[range].lowercased()
            if !token.isEmpty {
                tokens.append(WordToken(normalized: token, range: range))
            }
        }

        return tokens
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "'"
    }

    private static func trimSharedBoundaryCharacters(
        existingText: String,
        incomingRemainder: String
    ) -> String {
        guard !incomingRemainder.isEmpty else {
            return ""
        }

        let boundaryPrefix = String(incomingRemainder.prefix { $0.isWhitespace || $0.isPunctuation })
        guard !boundaryPrefix.isEmpty else {
            return incomingRemainder
        }

        let boundaryCharacters = Array(boundaryPrefix)
        for overlapCount in stride(from: boundaryCharacters.count, through: 1, by: -1) {
            let candidate = String(boundaryCharacters.prefix(overlapCount))
            if existingText.hasSuffix(candidate) {
                let dropIndex = incomingRemainder.index(
                    incomingRemainder.startIndex,
                    offsetBy: overlapCount
                )
                return String(incomingRemainder[dropIndex...])
            }
        }

        return incomingRemainder
    }
}

private actor WhisperLiveHotkeySession {
    private let configuration = LiveWhisperSessionConfiguration()
    private let engine: UnsafeSendableBox<WhisperEngine>
    private let settings: Settings
    private let updateHandler: @Sendable (LiveTranscriptionUpdate) -> Void

    private var accumulator: LiveTranscriptionAccumulator
    private var sampleBuffer: [Float] = []
    private var totalReceivedSamples = 0
    private var trimmedLeadingSamples = 0
    private var lastScheduledDecodeSample = 0
    private var currentDecodeTask: Task<Void, Never>?
    private var isFinishing = false
    private var lastUpdate = LiveTranscriptionUpdate.empty

    init(
        engine: WhisperEngine,
        settings: Settings,
        addSpaceAfterSentence: Bool,
        updateHandler: @escaping @Sendable (LiveTranscriptionUpdate) -> Void
    ) {
        self.engine = UnsafeSendableBox(engine)
        self.settings = settings
        self.updateHandler = updateHandler
        self.accumulator = LiveTranscriptionAccumulator(addSpaceAfterSentence: addSpaceAfterSentence)
    }

    func append(samples: [Float]) {
        guard !samples.isEmpty, !isFinishing else {
            return
        }

        sampleBuffer.append(contentsOf: samples)
        totalReceivedSamples += samples.count
        trimBufferIfNeeded()
        scheduleDecodeIfNeeded()
    }

    func finish() async -> LiveTranscriptionUpdate {
        isFinishing = true

        if let currentDecodeTask {
            await currentDecodeTask.value
        }

        if let finalSnapshot = makeDecodeSnapshot(isFinal: true) {
            lastScheduledDecodeSample = totalReceivedSamples
            startDecode(for: finalSnapshot)
            if let currentDecodeTask {
                await currentDecodeTask.value
            }
        }

        if !lastUpdate.isFinal {
            lastUpdate = LiveTranscriptionUpdate(
                committedText: lastUpdate.committedText,
                committedDelta: "",
                previewTail: "",
                committedEndTime: lastUpdate.committedEndTime,
                isFinal: true
            )
            updateHandler(lastUpdate)
        }

        return lastUpdate
    }

    func cancel() {
        isFinishing = true
        engine.value.cancelTranscription()
        currentDecodeTask?.cancel()
        currentDecodeTask = nil
    }

    private func scheduleDecodeIfNeeded() {
        guard currentDecodeTask == nil,
              let snapshot = makeDecodeSnapshot(isFinal: false)
        else {
            return
        }

        lastScheduledDecodeSample = totalReceivedSamples
        startDecode(for: snapshot)
    }

    private func startDecode(for snapshot: DecodeSnapshot) {
        currentDecodeTask = Task { [engine, settings] in
            do {
                let decodedSegments = try await engine.value.transcribeSamples(snapshot.samples, settings: settings)
                let offsetSegments = decodedSegments.map { segment in
                    WhisperSegmentResult(
                        text: segment.text,
                        startTime: segment.startTime + snapshot.startTime,
                        endTime: segment.endTime + snapshot.startTime,
                        tokens: segment.tokens.map { token in
                            WhisperTimedToken(
                                id: token.id,
                                text: token.text,
                                startTime: token.startTime + snapshot.startTime,
                                endTime: token.endTime + snapshot.startTime
                            )
                        }
                    )
                }

                self.handleDecodeCompletion(
                    segments: offsetSegments,
                    liveEdge: snapshot.liveEdge,
                    isFinal: snapshot.isFinal
                )
            } catch is CancellationError {
                self.handleDecodeCancellation()
            } catch {
                print("Live Whisper decode failed: \(error)")
                self.handleDecodeFailure()
            }
        }
    }

    private func handleDecodeCompletion(
        segments: [WhisperSegmentResult],
        liveEdge: Double,
        isFinal: Bool
    ) {
        currentDecodeTask = nil
        lastUpdate = accumulator.apply(
            segments: segments,
            liveEdge: liveEdge,
            isFinal: isFinal,
            stabilityBufferSeconds: LiveWhisperSessionConfiguration.stabilityBufferSeconds
        )
        updateHandler(lastUpdate)

        if !isFinishing {
            scheduleDecodeIfNeeded()
        }
    }

    private func handleDecodeCancellation() {
        currentDecodeTask = nil
    }

    private func handleDecodeFailure() {
        currentDecodeTask = nil
        if !isFinishing {
            scheduleDecodeIfNeeded()
        }
    }

    private func makeDecodeSnapshot(isFinal: Bool) -> DecodeSnapshot? {
        guard !sampleBuffer.isEmpty else {
            return nil
        }

        if !isFinal {
            guard totalReceivedSamples >= configuration.minimumWarmupSamples,
                  totalReceivedSamples - lastScheduledDecodeSample >= configuration.decodeCadenceSamples
            else {
                return nil
            }
        }

        let liveEdgeSample = totalReceivedSamples
        let windowStartSample = max(0, liveEdgeSample - configuration.maxWindowSamples)
        let overlapStartSample = max(
            0,
            Int(
                max(
                    0,
                    accumulator.lastCommittedEndTime - LiveWhisperSessionConfiguration.overlapSeconds
                ) * LiveWhisperSessionConfiguration.sampleRate
            )
        )
        let availableStartSample = trimmedLeadingSamples
        let startSample = max(max(windowStartSample, overlapStartSample), availableStartSample)
        let startIndex = max(0, startSample - trimmedLeadingSamples)

        return DecodeSnapshot(
            samples: Array(sampleBuffer[startIndex...]),
            startTime: Double(startSample) / LiveWhisperSessionConfiguration.sampleRate,
            liveEdge: Double(totalReceivedSamples) / LiveWhisperSessionConfiguration.sampleRate,
            isFinal: isFinal
        )
    }

    private func trimBufferIfNeeded() {
        let overflow = sampleBuffer.count - configuration.retainedBufferSamples
        guard overflow > 0 else {
            return
        }

        sampleBuffer.removeFirst(overflow)
        trimmedLeadingSamples += overflow
    }
}

@MainActor
class TranscriptionService: ObservableObject {
    static let shared = TranscriptionService()
    
    @Published private(set) var isTranscribing = false
    @Published private(set) var transcribedText = ""
    @Published private(set) var currentSegment = ""
    @Published private(set) var isLoading = false
    @Published private(set) var progress: Float = 0.0
    @Published private(set) var isConverting = false
    @Published private(set) var conversionProgress: Float = 0.0
    
    private var currentEngine: TranscriptionEngine?
    private var totalDuration: Float = 0.0
    private var transcriptionTask: Task<String, Error>? = nil
    private var isCancelled = false
    private var engineLoadTask: Task<TranscriptionEngine, Error>?
    private var lastEngineLoadError: Error?
    private var liveWhisperSession: WhisperLiveHotkeySession?
    private var liveInsertionSession: FocusedTextInsertionSession?
    private var pendingLiveSamples: [[Float]] = []
    private var lastAppliedLiveUpdate: LiveTranscriptionUpdate?
    
    init() {
        loadEngine()
    }

    var isLiveWhisperSessionActive: Bool {
        liveWhisperSession != nil
    }

    var isBatchTranscriptionActive: Bool {
        transcriptionTask != nil
    }
    
    func cancelTranscription() {
        isCancelled = true
        currentEngine?.cancelTranscription()
        transcriptionTask?.cancel()
        transcriptionTask = nil

        Task {
            await self.cancelLiveWhisperHotkeySession()
        }
        
        isTranscribing = false
        currentSegment = ""
        progress = 0.0
        isCancelled = false
    }
    
    private func loadEngine() {
        let selectedEngine = AppPreferences.shared.selectedEngine
        print("Loading engine: \(selectedEngine)")
        
        isLoading = true

        engineLoadTask?.cancel()
        engineLoadTask = Task(priority: .userInitiated) { [selectedEngine] in
            let engine = Self.createEngine(named: selectedEngine)
            try await engine.initialize()
            return engine
        }

        Task { [weak self] in
            guard let self = self, let engineLoadTask = self.engineLoadTask else { return }

            do {
                let engine = try await engineLoadTask.value
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    self.currentEngine = engine
                    self.lastEngineLoadError = nil
                    self.isLoading = false
                    print("Engine loaded: \(selectedEngine)")
                }
            } catch {
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    self.currentEngine = nil
                    self.lastEngineLoadError = error
                    self.isLoading = false
                    print("Failed to load engine: \(error)")
                }
            }
        }
    }
    
    func reloadEngine() {
        loadEngine()
    }
    
    func reloadModel(with path: String) {
        if AppPreferences.shared.selectedEngine == "whisper" {
            AppPreferences.shared.selectedWhisperModelPath = path
            reloadEngine()
        }
    }

    func startLiveWhisperHotkeySession(settings: Settings) async throws {
        await cancelLiveWhisperHotkeySession()

        isCancelled = false
        isTranscribing = true
        isConverting = false
        progress = 0.0
        conversionProgress = 0.0
        transcribedText = ""
        currentSegment = ""
        lastAppliedLiveUpdate = nil

        let engine = try await ensureWhisperEngineLoaded()
        let session = WhisperLiveHotkeySession(
            engine: engine,
            settings: settings,
            addSpaceAfterSentence: AppPreferences.shared.addSpaceAfterSentence
        ) { [weak self] update in
            Task { @MainActor in
                self?.applyLiveUpdate(update)
            }
        }

        liveWhisperSession = session
        liveInsertionSession = FocusedTextInsertionSession()

        let bufferedSamples = pendingLiveSamples
        pendingLiveSamples.removeAll()

        for samples in bufferedSamples {
            await session.append(samples: samples)
        }
    }

    func consumeLiveWhisperSamples(_ samples: [Float]) {
        guard !samples.isEmpty else {
            return
        }

        if let liveWhisperSession {
            Task {
                await liveWhisperSession.append(samples: samples)
            }
        } else {
            pendingLiveSamples.append(samples)
        }
    }

    func finishLiveWhisperHotkeySession() async -> LiveTranscriptionUpdate? {
        guard let liveWhisperSession else {
            _ = liveInsertionSession?.finalizeReleaseInsertion()
            liveInsertionSession = nil
            pendingLiveSamples.removeAll()
            isTranscribing = false
            currentSegment = ""
            lastAppliedLiveUpdate = nil
            return nil
        }

        let update = await liveWhisperSession.finish()
        applyLiveUpdate(update)
        _ = liveInsertionSession?.finalizeReleaseInsertion()

        self.liveWhisperSession = nil
        liveInsertionSession = nil
        pendingLiveSamples.removeAll()
        currentSegment = ""
        isTranscribing = false
        progress = 1.0
        lastAppliedLiveUpdate = nil

        return update
    }

    func cancelLiveWhisperHotkeySession() async {
        if let liveWhisperSession {
            await liveWhisperSession.cancel()
        }

        liveWhisperSession = nil
        liveInsertionSession = nil
        pendingLiveSamples.removeAll()
        lastAppliedLiveUpdate = nil
        currentSegment = ""
        transcribedText = ""
        isTranscribing = false
        progress = 0.0
    }
    
    func transcribeAudio(url: URL, settings: Settings) async throws -> String {
        await MainActor.run {
            self.progress = 0.0
            self.conversionProgress = 0.0
            self.isConverting = true
            self.isTranscribing = true
            self.transcribedText = ""
            self.currentSegment = ""
            self.isCancelled = false
        }
        
        defer {
            Task { @MainActor in
                self.isTranscribing = false
                self.isConverting = false
                self.currentSegment = ""
                if !self.isCancelled {
                    self.progress = 1.0
                }
                self.transcriptionTask = nil
            }
        }
        
        let durationInSeconds: Float = await (try? Task.detached(priority: .userInitiated) {
            let asset = AVAsset(url: url)
            let duration = try await asset.load(.duration)
            return Float(CMTimeGetSeconds(duration))
        }.value) ?? 0.0
        
        await MainActor.run {
            self.totalDuration = durationInSeconds
        }
        
        let engine = try await ensureEngineLoaded()
        
        if let whisperEngine = engine as? WhisperEngine {
            whisperEngine.onProgressUpdate = { [weak self] newProgress in
                Task { @MainActor in
                    guard let self = self, !self.isCancelled else { return }
                    self.progress = newProgress
                }
            }
        } else if let fluidEngine = engine as? FluidAudioEngine {
            fluidEngine.onProgressUpdate = { [weak self] newProgress in
                Task { @MainActor in
                    guard let self = self, !self.isCancelled else { return }
                    self.progress = newProgress
                }
            }
        }
        
        let service = UnsafeSendableBox(self)
        let task = Task.detached(priority: .userInitiated) { [engine, service] in
            try Task.checkCancellation()
            
            let cancelled = await MainActor.run {
                service.value.isCancelled
            }
            
            guard !cancelled else {
                throw CancellationError()
            }
            
            let result = try await engine.transcribeAudio(url: url, settings: settings)
            
            try Task.checkCancellation()
            
            let finalCancelled = await MainActor.run {
                service.value.isCancelled
            }
            
            await MainActor.run {
                guard !service.value.isCancelled else { return }
                service.value.transcribedText = result
                service.value.progress = 1.0
            }
            
            guard !finalCancelled else {
                throw CancellationError()
            }
            
            return result
        }
        
        await MainActor.run {
            self.transcriptionTask = task
        }
        
        do {
            return try await task.value
        } catch is CancellationError {
            await MainActor.run {
                self.isCancelled = true
            }
            throw TranscriptionError.processingFailed
        }
    }

    private func applyLiveUpdate(_ update: LiveTranscriptionUpdate) {
        guard lastAppliedLiveUpdate != update else {
            return
        }

        lastAppliedLiveUpdate = update
        transcribedText = update.committedText
        currentSegment = update.previewTail

        if !update.committedDelta.isEmpty {
            liveInsertionSession?.appendCommittedDelta(update.committedDelta)
        }

        if update.isFinal {
            currentSegment = ""
        }
    }

    private func ensureWhisperEngineLoaded() async throws -> WhisperEngine {
        let engine = try await ensureEngineLoaded()
        guard let whisperEngine = engine as? WhisperEngine else {
            throw TranscriptionError.contextInitializationFailed
        }
        return whisperEngine
    }

    private func ensureEngineLoaded() async throws -> TranscriptionEngine {
        if let engine = currentEngine {
            return engine
        }

        if let task = engineLoadTask {
            do {
                let engine = try await task.value
                await MainActor.run {
                    self.currentEngine = engine
                    self.lastEngineLoadError = nil
                    self.isLoading = false
                }
                return engine
            } catch {
                await MainActor.run {
                    self.currentEngine = nil
                    self.lastEngineLoadError = error
                    self.isLoading = false
                }
                throw error
            }
        }

        let selectedEngine = AppPreferences.shared.selectedEngine
        await MainActor.run {
            self.isLoading = true
        }

        do {
            let engine = Self.createEngine(named: selectedEngine)
            try await engine.initialize()
            await MainActor.run {
                self.currentEngine = engine
                self.lastEngineLoadError = nil
                self.isLoading = false
            }
            return engine
        } catch {
            await MainActor.run {
                self.currentEngine = nil
                self.lastEngineLoadError = error
                self.isLoading = false
            }
            throw error
        }
    }

    private static func createEngine(named selectedEngine: String) -> TranscriptionEngine {
        if selectedEngine == "fluidaudio" {
            return FluidAudioEngine()
        }
        return WhisperEngine()
    }
}

enum TranscriptionError: Error {
    case contextInitializationFailed
    case audioConversionFailed
    case processingFailed
}
