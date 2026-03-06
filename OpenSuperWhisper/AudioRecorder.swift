import AVFoundation
import Foundation
import SwiftUI
import AppKit
import CoreAudio

class AudioRecorder: NSObject, ObservableObject {
    typealias LiveSampleHandler = @Sendable ([Float]) -> Void

    @Published var isRecording = false
    @Published var isPlaying = false
    @Published var currentlyPlayingURL: URL?
    @Published var canRecord = false
    @Published var isConnecting = false
    
    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var notificationSound: NSSound?
    private let temporaryDirectory: URL
    private var currentRecordingURL: URL?
    private var notificationObserver: Any?
    private var microphoneChangeObserver: Any?
    private var connectionCheckTimer: DispatchSourceTimer?
    private var recordingDeviceID: AudioDeviceID?
    private var liveAudioEngine: AVAudioEngine?
    private var liveAudioFile: AVAudioFile?
    private var liveAudioConverter: AVAudioConverter?
    private var liveSampleHandler: LiveSampleHandler?
    private let liveCaptureQueue = DispatchQueue(label: "OpenSuperWhisper.AudioRecorder.liveCapture")
    private var activeRecordingMode: RecordingMode = .none
    private var didReceiveLiveSamples = false

    private enum RecordingMode {
        case none
        case recorder
        case liveHotkey
    }

    // MARK: - Singleton Instance

    static let shared = AudioRecorder()
    
    override private init() {
        let tempDir = FileManager.default.temporaryDirectory
        temporaryDirectory = tempDir.appendingPathComponent("temp_recordings")
        
        super.init()
        createTemporaryDirectoryIfNeeded()
        setup()
    }
    
    deinit {
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = microphoneChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    private func setup() {
        updateCanRecordStatus()
        
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .AVCaptureDeviceWasConnected,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateCanRecordStatus()
        }
        
        NotificationCenter.default.addObserver(
            forName: .AVCaptureDeviceWasDisconnected,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateCanRecordStatus()
        }
        
        microphoneChangeObserver = NotificationCenter.default.addObserver(
            forName: .microphoneDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateCanRecordStatus()
        }
    }
    
    private func updateCanRecordStatus() {
        canRecord = MicrophoneService.shared.getActiveMicrophone() != nil
    }
    
    private func createTemporaryDirectoryIfNeeded() {
        do {
            try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        } catch {
            print("Failed to create temporary recordings directory: \(error)")
        }
    }
    
    private func playNotificationSound() {
        // Try to play using NSSound first
        guard let soundURL = Bundle.main.url(forResource: "notification", withExtension: "mp3") else {
            print("Failed to find notification sound file")
            // Fall back to system sound if notification.mp3 is not found
            NSSound.beep()
            return
        }
        
        if let sound = NSSound(contentsOf: soundURL, byReference: false) {
            // Set maximum volume to ensure it's audible
            sound.volume = 0.3
            sound.play()
            notificationSound = sound
        } else {
            print("Failed to create NSSound from URL, falling back to system beep")
            // Fall back to system beep if NSSound creation fails
            NSSound.beep()
        }
    }
    
    func startRecording() {
        guard canRecord else {
            print("Cannot start recording - no audio input available")
            return
        }
        
        if isRecording || isConnecting {
            print("stop recording while recording")
            _ = stopRecording()
        }
        
        if AppPreferences.shared.playSoundOnRecordStart {
            playNotificationSound()
        }
        
        let timestamp = Int(Date().timeIntervalSince1970)
        let filename = "\(timestamp).wav"
        let fileURL = temporaryDirectory.appendingPathComponent(filename)
        currentRecordingURL = fileURL
        
        print("start record file to \(fileURL)")

        prepareSystemInput()
        
        let requiresConnection = MicrophoneService.shared.isActiveMicrophoneRequiresConnection()
        updateRecordingState(isRecording: false, isConnecting: requiresConnection)
        startRecordingWithRecorder(fileURL: fileURL, monitorConnection: requiresConnection)
    }

    func startLiveHotkeyCapture(onSamples: @escaping LiveSampleHandler) {
        guard canRecord else {
            print("Cannot start live capture - no audio input available")
            return
        }

        if isRecording || isConnecting {
            cancelRecording()
        }

        if AppPreferences.shared.playSoundOnRecordStart {
            playNotificationSound()
        }

        let timestamp = Int(Date().timeIntervalSince1970)
        let filename = "\(timestamp).wav"
        let fileURL = temporaryDirectory.appendingPathComponent(filename)
        currentRecordingURL = fileURL
        liveSampleHandler = onSamples
        didReceiveLiveSamples = false

        prepareSystemInput()

        let requiresConnection = MicrophoneService.shared.isActiveMicrophoneRequiresConnection()
        updateRecordingState(isRecording: false, isConnecting: requiresConnection)

        do {
            try startRecordingWithAudioEngine(fileURL: fileURL, monitorConnection: requiresConnection)
        } catch {
            print("Failed to start live capture: \(error)")
            currentRecordingURL = nil
            liveSampleHandler = nil
            liveAudioFile = nil
            liveAudioConverter = nil
            liveAudioEngine = nil
            activeRecordingMode = .none
            updateRecordingState(isRecording: false, isConnecting: false)
        }
    }
    
    private func startRecordingWithRecorder(fileURL: URL, monitorConnection: Bool) {
        var channelCount = 1
        if let activeMic = MicrophoneService.shared.getActiveMicrophone() {
            channelCount = MicrophoneService.shared.getInputChannelCount(for: activeMic)
            print("Recording with \(channelCount) input channel(s) from \(activeMic.displayName)")
        }
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: channelCount,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = monitorConnection
            audioRecorder?.record()
            activeRecordingMode = .recorder
            if monitorConnection {
                startConnectionMonitoring()
            } else {
                updateRecordingState(isRecording: true, isConnecting: false)
            }
            print("Recording started successfully")
        } catch {
            print("Failed to start recording: \(error)")
            currentRecordingURL = nil
            updateRecordingState(isRecording: false, isConnecting: false)
        }
    }

    private func startRecordingWithAudioEngine(fileURL: URL, monitorConnection: Bool) throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)

        guard let targetFormat = makeTargetFormat(channelCount: inputFormat.channelCount),
              let converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        else {
            throw NSError(domain: "AudioRecorder", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to configure live audio conversion."
            ])
        }

        converter.sampleRateConverterQuality = AVAudioQuality.medium.rawValue

        let audioFile = try AVAudioFile(
            forWriting: fileURL,
            settings: targetFormat.settings,
            commonFormat: targetFormat.commonFormat,
            interleaved: targetFormat.isInterleaved
        )

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self, let copiedBuffer = self.copyPCMBuffer(buffer) else { return }

            self.liveCaptureQueue.async { [weak self] in
                self?.processLiveCaptureBuffer(copiedBuffer, monitorConnection: monitorConnection)
            }
        }

        engine.prepare()
        try engine.start()

        liveAudioEngine = engine
        liveAudioFile = audioFile
        liveAudioConverter = converter
        activeRecordingMode = .liveHotkey

        if !monitorConnection {
            updateRecordingState(isRecording: true, isConnecting: false)
        }

        print("Live capture started successfully")
    }
    
    func stopRecording() -> URL? {
        if activeRecordingMode == .liveHotkey {
            return stopLiveHotkeyCapture()
        }

        audioRecorder?.stop()
        audioRecorder = nil
        updateRecordingState(isRecording: false, isConnecting: false)
        stopConnectionMonitoring()
        activeRecordingMode = .none
        
        if let url = currentRecordingURL, shouldDiscardShortRecording(at: url) {
            try? FileManager.default.removeItem(at: url)
            currentRecordingURL = nil
            return nil
        }
        
        let url = currentRecordingURL
        currentRecordingURL = nil
        return url
    }

    func stopLiveHotkeyCapture() -> URL? {
        guard activeRecordingMode == .liveHotkey else {
            return stopRecording()
        }

        if let inputNode = liveAudioEngine?.inputNode {
            inputNode.removeTap(onBus: 0)
        }
        liveAudioEngine?.stop()
        liveAudioEngine = nil

        liveCaptureQueue.sync {}

        liveAudioFile = nil
        liveAudioConverter = nil
        liveSampleHandler = nil
        activeRecordingMode = .none
        didReceiveLiveSamples = false

        updateRecordingState(isRecording: false, isConnecting: false)

        if let url = currentRecordingURL, shouldDiscardShortRecording(at: url) {
            try? FileManager.default.removeItem(at: url)
            currentRecordingURL = nil
            return nil
        }

        let url = currentRecordingURL
        currentRecordingURL = nil
        return url
    }
    
    func cancelRecording() {
        if activeRecordingMode == .liveHotkey {
            if let inputNode = liveAudioEngine?.inputNode {
                inputNode.removeTap(onBus: 0)
            }
            liveAudioEngine?.stop()
            liveAudioEngine = nil
            liveCaptureQueue.sync {}
            liveAudioFile = nil
            liveAudioConverter = nil
            liveSampleHandler = nil
            activeRecordingMode = .none
            didReceiveLiveSamples = false
        }

        audioRecorder?.stop()
        audioRecorder = nil
        activeRecordingMode = .none
        updateRecordingState(isRecording: false, isConnecting: false)
        stopConnectionMonitoring()
        
        if let url = currentRecordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        currentRecordingURL = nil
    }
    
    
    func moveTemporaryRecording(from tempURL: URL, to finalURL: URL) throws {

        let directory = finalURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        if FileManager.default.fileExists(atPath: finalURL.path) {
            try FileManager.default.removeItem(at: finalURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: finalURL)
    }
    
    func playRecording(url: URL) {
        // Stop current playback if any
        stopPlaying()
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.play()
            isPlaying = true
            currentlyPlayingURL = url
        } catch {
            print("Failed to play recording: \(error), url: \(url)")
            isPlaying = false
            currentlyPlayingURL = nil
        }
    }
    
    func stopPlaying() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        currentlyPlayingURL = nil
    }

    private func prepareSystemInput() {
        #if os(macOS)
        if let activeMic = MicrophoneService.shared.getActiveMicrophone() {
            _ = MicrophoneService.shared.setAsSystemDefaultInput(activeMic)
            print("Set system default input to: \(activeMic.displayName)")

            if let deviceID = MicrophoneService.shared.getCoreAudioDeviceID(for: activeMic) {
                recordingDeviceID = deviceID
            }
        }
        #endif
    }

    private func shouldDiscardShortRecording(at url: URL) -> Bool {
        guard let duration = try? AVAudioPlayer(contentsOf: url).duration else {
            return false
        }
        return duration < 1.0
    }
    
    private func updateRecordingState(isRecording: Bool, isConnecting: Bool) {
        DispatchQueue.main.async {
            self.isRecording = isRecording
            self.isConnecting = isConnecting
        }
    }

    private func processLiveCaptureBuffer(_ buffer: AVAudioPCMBuffer, monitorConnection: Bool) {
        guard let converter = liveAudioConverter,
              let audioFile = liveAudioFile
        else {
            return
        }

        let ratio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 256

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: converter.outputFormat,
            frameCapacity: outputCapacity
        ) else {
            return
        }

        var inputConsumed = false
        var error: NSError?

        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        outputBuffer.frameLength = 0
        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        if let error {
            print("Live conversion error: \(error)")
            return
        }

        guard outputBuffer.frameLength > 0 else {
            return
        }

        do {
            try audioFile.write(from: outputBuffer)
        } catch {
            print("Failed to write live capture buffer: \(error)")
        }

        if monitorConnection && !didReceiveLiveSamples {
            didReceiveLiveSamples = true
            updateRecordingState(isRecording: true, isConnecting: false)
        }

        var samples = [Float]()
        appendMixedSamples(from: outputBuffer, to: &samples)
        guard !samples.isEmpty else {
            return
        }

        liveSampleHandler?(samples)
    }

    private func copyPCMBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(
            pcmFormat: buffer.format,
            frameCapacity: buffer.frameCapacity
        ) else {
            return nil
        }

        copy.frameLength = buffer.frameLength

        let sourceBuffers = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: buffer.audioBufferList)
        )
        let destinationBuffers = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)

        guard sourceBuffers.count == destinationBuffers.count else {
            return nil
        }

        for index in 0..<sourceBuffers.count {
            let source = sourceBuffers[index]
            var destination = destinationBuffers[index]
            guard let sourceData = source.mData, let destinationData = destination.mData else {
                continue
            }
            memcpy(destinationData, sourceData, Int(source.mDataByteSize))
            destination.mDataByteSize = source.mDataByteSize
            destinationBuffers[index] = destination
        }

        return copy
    }

    private func appendMixedSamples(from buffer: AVAudioPCMBuffer, to output: inout [Float]) {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0, let channelData = buffer.floatChannelData else { return }

        let channelCount = Int(buffer.format.channelCount)
        if channelCount == 1 {
            let mono = UnsafeBufferPointer(start: channelData[0], count: frameCount)
            output.append(contentsOf: mono)
            return
        }

        let normalization = 1.0 / Float(channelCount)
        output.reserveCapacity(output.count + frameCount)

        for frame in 0..<frameCount {
            var mixed: Float = 0
            for channel in 0..<channelCount {
                mixed += channelData[channel][frame]
            }
            output.append(mixed * normalization)
        }
    }

    private func makeTargetFormat(channelCount: AVAudioChannelCount) -> AVAudioFormat? {
        guard channelCount > 0 else { return nil }

        let layoutTag = AudioChannelLayoutTag(
            kAudioChannelLayoutTag_DiscreteInOrder | UInt32(channelCount)
        )
        guard let channelLayout = AVAudioChannelLayout(layoutTag: layoutTag) else {
            return nil
        }

        return AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            interleaved: false,
            channelLayout: channelLayout
        )
    }
    
    private func startConnectionMonitoring() {
        stopConnectionMonitoring()
        
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))
        timer.schedule(deadline: .now() + 0.05, repeating: 0.05)
        let initialFileSize: Int64 = 4096
        var growthCount = 0
        
        timer.setEventHandler { [weak self] in
            guard let self = self, let _ = self.audioRecorder, let url = self.currentRecordingURL else { return }
            
            let currentFileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            let totalGrowth = currentFileSize - initialFileSize
            
            if totalGrowth > 8000 {
                growthCount += 1
            }
            
            if growthCount >= 2 {
                self.stopConnectionMonitoring()
                self.updateRecordingState(isRecording: true, isConnecting: false)
            }
        }
        connectionCheckTimer = timer
        timer.resume()
    }
    
    private func stopConnectionMonitoring() {
        connectionCheckTimer?.cancel()
        connectionCheckTimer = nil
    }
}

extension AudioRecorder: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            currentRecordingURL = nil
        }
    }
}

extension AudioRecorder: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        currentlyPlayingURL = nil
    }
}
