import Foundation
import AVFoundation
import CoreAudioTypes

private class ProgressContext {
    var onProgress: ((Float) -> Void)?
    private var _lastReportedProgress: Float = 0.0
    private let lock = NSLock()
    
    var lastReportedProgress: Float {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _lastReportedProgress
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _lastReportedProgress = newValue
        }
    }
}

struct WhisperSegmentResult: Equatable, Sendable {
    let text: String
    let startTime: Double
    let endTime: Double
    let tokens: [WhisperTimedToken]

    init(
        text: String,
        startTime: Double,
        endTime: Double,
        tokens: [WhisperTimedToken] = []
    ) {
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.tokens = tokens
    }
}

struct WhisperTimedToken: Equatable, Sendable {
    let id: WhisperToken
    let text: String
    let startTime: Double
    let endTime: Double
}

class WhisperEngine: TranscriptionEngine {
    private static let whisperControlTokenPattern = #"\[_[A-Z0-9]+(?:_[A-Z0-9]+)*_?\]"#
    private static let knownHallucinationNormalizedPhrases = [
        "ask for follow up changes",
        "ask follow up changes",
    ]

    var engineName: String { "Whisper" }
    
    private var context: MyWhisperContext?
    private let stateLock = NSLock()
    private var _isCancelled = false
    private var _abortFlag: UnsafeMutablePointer<Bool>?
    private var progressContext: ProgressContext?
    
    private var isCancelled: Bool {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _isCancelled
        }
        set {
            stateLock.lock()
            defer { stateLock.unlock() }
            _isCancelled = newValue
        }
    }
    
    private var abortFlag: UnsafeMutablePointer<Bool>? {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _abortFlag
        }
        set {
            stateLock.lock()
            defer { stateLock.unlock() }
            _abortFlag = newValue
        }
    }
    
    var onProgressUpdate: ((Float) -> Void)?
    
    var isModelLoaded: Bool {
        context != nil
    }
    
    func initialize() async throws {
        let fileManager = FileManager.default
        let preferredModelPath = AppPreferences.shared.selectedWhisperModelPath ?? AppPreferences.shared.selectedModelPath

        let resolvedModelPath: String?
        if let preferredModelPath, fileManager.fileExists(atPath: preferredModelPath) {
            resolvedModelPath = preferredModelPath
        } else {
            let fallbackModelURL = WhisperModelManager.shared.getAvailableModels().first
            resolvedModelPath = fallbackModelURL?.path
            if let fallbackPath = fallbackModelURL?.path {
                AppPreferences.shared.selectedWhisperModelPath = fallbackPath
            }
        }

        guard let modelPath = resolvedModelPath else {
            throw TranscriptionError.contextInitializationFailed
        }
        
        let params = WhisperContextParams()
        context = MyWhisperContext.initFromFile(path: modelPath, params: params)
        
        guard context != nil else {
            throw TranscriptionError.contextInitializationFailed
        }
    }
    
    func transcribeAudio(url: URL, settings: Settings) async throws -> String {
        // Notify conversion start (0-10% is conversion phase)
        onProgressUpdate?(0.05)
        
        guard let samples = try await convertAudioToPCM(fileURL: url) else {
            throw TranscriptionError.audioConversionFailed
        }
        
        // Conversion done, now processing
        onProgressUpdate?(0.10)
        
        let segments = try await runSampleTranscription(
            samples,
            settings: settings,
            includeSegmentTimestamps: false,
            includeTokenTimestamps: false
        )
        let cleanedText = formatBatchText(from: segments, settings: settings)
        
        var processedText = cleanedText
        if settings.shouldApplyAsianAutocorrect && !cleanedText.isEmpty {
            processedText = AutocorrectWrapper.format(cleanedText)
        }
        
        return processedText.isEmpty ? "No speech detected in the audio" : processedText
    }

    func transcribeSamples(_ samples: [Float], settings: Settings) async throws -> [WhisperSegmentResult] {
        try await runSampleTranscription(
            samples,
            settings: settings,
            includeSegmentTimestamps: true,
            includeTokenTimestamps: true
        )
    }

    private func runSampleTranscription(
        _ samples: [Float],
        settings: Settings,
        includeSegmentTimestamps: Bool,
        includeTokenTimestamps: Bool
    ) async throws -> [WhisperSegmentResult] {
        guard let context = context else {
            throw TranscriptionError.contextInitializationFailed
        }

        guard !samples.isEmpty else {
            return []
        }

        try prepareForTranscription()
        defer {
            finishTranscription()
        }

        var params = makeWhisperParams(
            for: settings,
            includeSegmentTimestamps: includeSegmentTimestamps,
            includeTokenTimestamps: includeTokenTimestamps
        )
        params.progressCallback = makeProgressCallback()
        params.progressCallbackUserData = progressContext.map { Unmanaged.passUnretained($0).toOpaque() }

        if settings.useBeamSearch {
            params.beamSearchBeamSize = Int32(settings.beamSize)
        }

        var cParams = params.toC()
        cParams.abort_callback = makeAbortCallback()

        if let abortFlag {
            cParams.abort_callback_user_data = UnsafeMutableRawPointer(abortFlag)
        }

        try Task.checkCancellation()

        guard context.full(samples: samples, params: &cParams) else {
            throw TranscriptionError.processingFailed
        }

        try Task.checkCancellation()
        return try extractSegments(
            from: context,
            includeTokenTimestamps: includeTokenTimestamps
        )
    }
    
    func cancelTranscription() {
        isCancelled = true
        if let abortFlag = abortFlag {
            abortFlag.pointee = true
        }
    }
    
    func getSupportedLanguages() -> [String] {
        return LanguageUtil.availableLanguages
    }

    private func prepareForTranscription() throws {
        isCancelled = false

        if abortFlag != nil {
            abortFlag?.deallocate()
        }
        abortFlag = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        abortFlag?.initialize(to: false)

        progressContext = ProgressContext()
        progressContext?.onProgress = onProgressUpdate

        try Task.checkCancellation()
    }

    private func finishTranscription() {
        abortFlag?.deallocate()
        abortFlag = nil
        progressContext = nil
    }

    private func makeWhisperParams(
        for settings: Settings,
        includeSegmentTimestamps: Bool,
        includeTokenTimestamps: Bool
    ) -> WhisperFullParams {
        let nThreads = max(2, min(ProcessInfo.processInfo.activeProcessorCount, 8))

        var params = WhisperFullParams()
        params.strategy = settings.useBeamSearch ? .beamSearch : .greedy
        params.nThreads = Int32(nThreads)
        params.noTimestamps = !includeSegmentTimestamps && !settings.showTimestamps
        params.suppressBlank = settings.suppressBlankAudio
        params.translate = settings.translateToEnglish
        let isAutoDetect = settings.selectedLanguage == "auto"
        params.language = isAutoDetect ? nil : settings.selectedLanguage
        params.detectLanguage = false
        params.temperature = Float(settings.temperature)
        params.noSpeechThold = Float(settings.noSpeechThreshold)
        params.initialPrompt = settings.initialPrompt.isEmpty ? nil : settings.initialPrompt
        params.printRealtime = true
        params.print_realtime = true
        params.tokenTimestamps = includeTokenTimestamps
        return params
    }

    private func makeAbortCallback() -> @convention(c) (UnsafeMutableRawPointer?) -> Bool {
        { userData in
            guard let userData else { return false }
            let flag = userData.assumingMemoryBound(to: Bool.self)
            return flag.pointee
        }
    }

    private func makeProgressCallback() -> (@convention(c) (OpaquePointer?, OpaquePointer?, Int32, UnsafeMutableRawPointer?) -> Void)? {
        { _, _, progressPercent, userData in
            guard let userData else { return }
            let ctx = Unmanaged<ProgressContext>.fromOpaque(userData).takeUnretainedValue()
            let normalizedProgress = 0.10 + (Float(progressPercent) / 100.0) * 0.85
            if normalizedProgress > ctx.lastReportedProgress {
                ctx.lastReportedProgress = normalizedProgress
                DispatchQueue.main.async {
                    ctx.onProgress?(normalizedProgress)
                }
            }
        }
    }

    private func extractSegments(
        from context: MyWhisperContext,
        includeTokenTimestamps: Bool
    ) throws -> [WhisperSegmentResult] {
        let nSegments = context.fullNSegments
        var segments: [WhisperSegmentResult] = []
        segments.reserveCapacity(nSegments)

        for i in 0..<nSegments {
            if i % 5 == 0 {
                try Task.checkCancellation()
            }

            guard let rawText = context.fullGetSegmentText(iSegment: i) else { continue }
            let cleanedText = cleanWhisperText(rawText)

            guard !cleanedText.isEmpty else { continue }

            let (startTime, endTime) = normalizedTimeRange(
                start: Double(context.fullGetSegmentT0(iSegment: i)) / 100.0,
                end: Double(context.fullGetSegmentT1(iSegment: i)) / 100.0
            )
            let tokens = includeTokenTimestamps
                ? try extractTimedTokens(
                    forSegment: i,
                    in: context,
                    fallbackStartTime: startTime,
                    fallbackEndTime: endTime
                )
                : []

            segments.append(
                WhisperSegmentResult(
                    text: cleanedText,
                    startTime: startTime,
                    endTime: endTime,
                    tokens: tokens
                )
            )
        }

        return segments
    }

    private func extractTimedTokens(
        forSegment segmentIndex: Int,
        in context: MyWhisperContext,
        fallbackStartTime: Double,
        fallbackEndTime: Double
    ) throws -> [WhisperTimedToken] {
        let nTokens = context.fullNTokens(iSegment: segmentIndex)
        guard nTokens > 0 else {
            return []
        }

        var tokens: [WhisperTimedToken] = []
        tokens.reserveCapacity(nTokens)

        for tokenIndex in 0..<nTokens {
            if tokenIndex % 32 == 0 {
                try Task.checkCancellation()
            }

            guard let rawTokenText = context.fullGetTokenText(iSegment: segmentIndex, iToken: tokenIndex) else {
                continue
            }

            let cleanedText = cleanWhisperTokenText(rawTokenText)
            guard !cleanedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }

            let tokenData = context.fullGetTokenData(iSegment: segmentIndex, iToken: tokenIndex)
            let hasExplicitTiming = tokenData.t0 != 0 || tokenData.t1 != 0
            let rawStartTime = hasExplicitTiming ? Double(tokenData.t0) / 100.0 : fallbackStartTime
            let rawEndTime = hasExplicitTiming ? Double(tokenData.t1) / 100.0 : fallbackEndTime
            let (startTime, endTime) = normalizedTimeRange(start: rawStartTime, end: rawEndTime)

            tokens.append(
                WhisperTimedToken(
                    id: tokenData.id,
                    text: cleanedText,
                    startTime: startTime,
                    endTime: endTime
                )
            )
        }

        return tokens
    }

    private func cleanWhisperText(_ text: String) -> String {
        sanitizeWhisperArtifacts(in: text)
            .replacingOccurrences(of: "[MUSIC]", with: "")
            .replacingOccurrences(of: "[BLANK_AUDIO]", with: "")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cleanWhisperTokenText(_ text: String) -> String {
        sanitizeWhisperArtifacts(in: text)
            .replacingOccurrences(of: "[MUSIC]", with: "")
            .replacingOccurrences(of: "[BLANK_AUDIO]", with: "")
    }

    private func sanitizeWhisperArtifacts(in text: String) -> String {
        var cleaned = text.replacingOccurrences(
            of: Self.whisperControlTokenPattern,
            with: "",
            options: .regularExpression
        )

        if Self.isKnownHallucinationPhrase(cleaned) {
            return ""
        }

        return cleaned
    }

    private static func isKnownHallucinationPhrase(_ text: String) -> Bool {
        let normalized = text
            .lowercased()
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return knownHallucinationNormalizedPhrases.contains(normalized)
    }

    private func normalizedTimeRange(start: Double, end: Double) -> (Double, Double) {
        let normalizedStart = max(0, start)
        let normalizedEnd = max(normalizedStart, end)
        return (normalizedStart, normalizedEnd)
    }

    private func formatBatchText(from segments: [WhisperSegmentResult], settings: Settings) -> String {
        let text = segments.reduce(into: "") { partialResult, segment in
            if settings.showTimestamps {
                partialResult += String(
                    format: "[%.1f->%.1f] ",
                    segment.startTime,
                    segment.endTime
                )
            }
            partialResult += segment.text + "\n"
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private nonisolated func resolveFileURL(_ fileURL: URL) throws -> (URL, Bool) {
        let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        guard data.count >= 12 else { return (fileURL, false) }

        let ext = fileURL.pathExtension.lowercased()

        let isMP4Header = data[4...7].elementsEqual([0x66, 0x74, 0x79, 0x70]) // "ftyp"
        if isMP4Header && ext != "m4a" && ext != "mp4" && ext != "m4b" && ext != "aac" {
            let tmpURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("m4a")
            try FileManager.default.copyItem(at: fileURL, to: tmpURL)
            return (tmpURL, true)
        }

        return (fileURL, false)
    }

    nonisolated func convertAudioToPCM(fileURL: URL) async throws -> [Float]? {
        return try await Task.detached(priority: .userInitiated) {
            let (resolvedURL, isTempFile) = try self.resolveFileURL(fileURL)
            defer {
                if isTempFile { try? FileManager.default.removeItem(at: resolvedURL) }
            }
            let audioFile = try AVAudioFile(forReading: resolvedURL)
            let sourceFormat = audioFile.processingFormat
            let totalFrames = audioFile.length
            
            guard let targetFormat = self.makeTargetFormat(channelCount: sourceFormat.channelCount) else {
                return nil
            }
            
            let sourceRate = sourceFormat.sampleRate
            let targetRate = targetFormat.sampleRate
            let ratio = targetRate / sourceRate
            
            // Use parallel processing for large files (> 10 seconds of audio)
            // Benchmarked: 4 cores = +339%, 8 cores = +609% improvement
            let minFramesForParallel = AVAudioFramePosition(sourceRate * 10)
            let workerCount = totalFrames > minFramesForParallel ? ProcessInfo.processInfo.activeProcessorCount : 1
            
            if workerCount == 1 {
                // Sequential processing for small files
                return try self.convertSequential(
                    fileURL: resolvedURL,
                    sourceFormat: sourceFormat,
                    targetFormat: targetFormat,
                    ratio: ratio,
                    totalFrames: totalFrames
                )
            }
            
            // Parallel processing: split file into segments
            let framesPerWorker = totalFrames / AVAudioFramePosition(workerCount)
            let outputFrameCount = Int(Double(totalFrames) * ratio) + 1024
            
            // Pre-allocate result array
            var result = [Float](repeating: 0, count: outputFrameCount)
            let resultLock = NSLock()
            var totalWritten = 0
            var hasError = false
            
            let group = DispatchGroup()
            let queue = DispatchQueue(label: "audio.conversion.parallel", attributes: .concurrent)
            
            for workerIndex in 0..<workerCount {
                group.enter()
                queue.async {
                    defer { group.leave() }
                    
                    guard !hasError else { return }
                    
                    let startFrame = AVAudioFramePosition(workerIndex) * framesPerWorker
                    let endFrame = workerIndex == workerCount - 1 ? totalFrames : startFrame + framesPerWorker
                    let segmentFrames = endFrame - startFrame
                    
                    guard let workerFile = try? AVAudioFile(forReading: resolvedURL) else {
                        hasError = true
                        return
                    }
                    
                    do {
                        workerFile.framePosition = startFrame
                    }
                    
                    guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
                        hasError = true
                        return
                    }
                    converter.sampleRateConverterQuality = AVAudioQuality.medium.rawValue
                    
                    let inputChunkSize: AVAudioFrameCount = 262144 // 256K for parallel
                    let outputChunkSize = AVAudioFrameCount(Double(inputChunkSize) * ratio) + 256
                    
                    guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: inputChunkSize),
                          let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputChunkSize) else {
                        hasError = true
                        return
                    }
                    
                    var segmentResult = [Float]()
                    let expectedOutputFrames = Int(Double(segmentFrames) * ratio) + 256
                    segmentResult.reserveCapacity(expectedOutputFrames)
                    
                    var framesRead: AVAudioFramePosition = 0
                    
                    while framesRead < segmentFrames {
                        let framesToRead = min(AVAudioFrameCount(segmentFrames - framesRead), inputChunkSize)
                        inputBuffer.frameLength = 0
                        
                        do {
                            try workerFile.read(into: inputBuffer, frameCount: framesToRead)
                        } catch {
                            break
                        }
                        
                        if inputBuffer.frameLength == 0 { break }
                        framesRead += AVAudioFramePosition(inputBuffer.frameLength)
                        
                        var inputConsumed = false
                        var convError: NSError?
                        
                        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                            if inputConsumed {
                                outStatus.pointee = .noDataNow
                                return nil
                            }
                            inputConsumed = true
                            outStatus.pointee = .haveData
                            return inputBuffer
                        }
                        
                        outputBuffer.frameLength = 0
                        converter.convert(to: outputBuffer, error: &convError, withInputFrom: inputBlock)
                        
                        self.appendMixedSamples(from: outputBuffer, to: &segmentResult)
                    }
                    
                    // Calculate output position for this segment
                    let outputStartIndex = Int(Double(startFrame) * ratio)
                    
                    resultLock.lock()
                    let writeEnd = min(outputStartIndex + segmentResult.count, result.count)
                    let writeCount = writeEnd - outputStartIndex
                    if writeCount > 0 && !segmentResult.isEmpty {
                        result.replaceSubrange(outputStartIndex..<writeEnd, with: segmentResult.prefix(writeCount))
                        totalWritten = max(totalWritten, writeEnd)
                    }
                    resultLock.unlock()
                }
            }
            
            group.wait()
            
            if hasError { return nil }
            
            // Trim to actual size
            if totalWritten > 0 && totalWritten < result.count {
                result.removeLast(result.count - totalWritten)
            }
            
            return result.isEmpty ? nil : result
        }.value
    }
    
    private nonisolated func convertSequential(
        fileURL: URL,
        sourceFormat: AVAudioFormat,
        targetFormat: AVAudioFormat,
        ratio: Double,
        totalFrames: AVAudioFramePosition
    ) throws -> [Float]? {
        let audioFile = try AVAudioFile(forReading: fileURL)
        
        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            return nil
        }
        converter.sampleRateConverterQuality = AVAudioQuality.medium.rawValue
        
        let outputFrameCount = AVAudioFrameCount(Double(totalFrames) * ratio) + 1024
        let inputChunkSize: AVAudioFrameCount = 1048576 // 1M for sequential
        
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: inputChunkSize) else {
            return nil
        }
        
        var result = [Float]()
        result.reserveCapacity(Int(outputFrameCount))
        
        let outputChunkSize = AVAudioFrameCount(Double(inputChunkSize) * ratio) + 256
        guard let chunkOutputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputChunkSize) else {
            return nil
        }
        
        while audioFile.framePosition < totalFrames {
            inputBuffer.frameLength = 0
            try audioFile.read(into: inputBuffer, frameCount: inputChunkSize)
            
            if inputBuffer.frameLength == 0 { break }
            
            var inputConsumed = false
            var error: NSError?
            
            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                if inputConsumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                inputConsumed = true
                outStatus.pointee = .haveData
                return inputBuffer
            }
            
            chunkOutputBuffer.frameLength = 0
            converter.convert(to: chunkOutputBuffer, error: &error, withInputFrom: inputBlock)
            
            if let error = error {
                print("Conversion error: \(error)")
                break
            }
            
            appendMixedSamples(from: chunkOutputBuffer, to: &result)
        }
        
        return result.isEmpty ? nil : result
    }
    
    private nonisolated func appendMixedSamples(from buffer: AVAudioPCMBuffer, to output: inout [Float]) {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0, let channelData = buffer.floatChannelData else { return }
        
        let channelCount = Int(buffer.format.channelCount)
        if channelCount == 1 {
            let mono = UnsafeBufferPointer(start: channelData[0], count: frameCount)
            output.append(contentsOf: mono)
            return
        }
        
        let activityThreshold: Float = 0.0001
        var activeChannels: [Int] = []
        activeChannels.reserveCapacity(channelCount)
        
        for channel in 0..<channelCount {
            let channelSamples = UnsafeBufferPointer(start: channelData[channel], count: frameCount)
            var energy: Float = 0
            for sample in channelSamples {
                energy += sample * sample
            }
            let rms = sqrtf(energy / Float(frameCount))
            if rms > activityThreshold {
                activeChannels.append(channel)
            }
        }
        
        if activeChannels.isEmpty {
            activeChannels = Array(0..<channelCount)
        }
        
        let normalization = 1.0 / Float(activeChannels.count)
        output.reserveCapacity(output.count + frameCount)
        
        for frame in 0..<frameCount {
            var mixed: Float = 0
            for channel in activeChannels {
                mixed += channelData[channel][frame]
            }
            output.append(mixed * normalization)
        }
    }
    
    nonisolated func makeTargetFormat(channelCount: AVAudioChannelCount) -> AVAudioFormat? {
        guard channelCount > 0 else { return nil }
        
        let layoutTag = AudioChannelLayoutTag(kAudioChannelLayoutTag_DiscreteInOrder | UInt32(channelCount))
        guard let channelLayout = AVAudioChannelLayout(layoutTag: layoutTag) else { return nil }
        
        return AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            interleaved: false,
            channelLayout: channelLayout
        )
    }
}
