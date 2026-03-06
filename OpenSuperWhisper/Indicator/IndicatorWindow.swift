import Cocoa
import Combine
import SwiftUI

enum RecordingState {
    case idle
    case connecting
    case recording
    case decoding
    case busy
}

@MainActor
protocol IndicatorViewDelegate: AnyObject {
    
    func didFinishDecoding()
}

@MainActor
class IndicatorViewModel: ObservableObject {
    @Published var state: RecordingState = .idle
    @Published var isBlinking = false
    @Published var recorder: AudioRecorder = .shared
    @Published var isVisible = false
    @Published var liveCommittedText = ""
    @Published var livePreviewText = ""
    
    var delegate: IndicatorViewDelegate?
    private var blinkTimer: Timer?
    private var hideTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    private let recordingStore: RecordingStore
    private let transcriptionService: TranscriptionService
    private let transcriptionQueue: TranscriptionQueue
    
    init() {
        self.recordingStore = RecordingStore.shared
        self.transcriptionService = TranscriptionService.shared
        self.transcriptionQueue = TranscriptionQueue.shared
        
        recorder.$isConnecting
            .receive(on: RunLoop.main)
            .sink { [weak self] isConnecting in
                guard let self = self else { return }
                if isConnecting {
                    self.state = .connecting
                    self.stopBlinking()
                }
            }
            .store(in: &cancellables)
        
        recorder.$isRecording
            .receive(on: RunLoop.main)
            .sink { [weak self] isRecording in
                guard let self = self else { return }
                if isRecording {
                    self.state = .recording
                    self.startBlinking()
                }
            }
            .store(in: &cancellables)

        transcriptionService.$transcribedText
            .combineLatest(transcriptionService.$currentSegment)
            .receive(on: RunLoop.main)
            .sink { [weak self] committedText, previewText in
                self?.liveCommittedText = committedText
                self?.livePreviewText = previewText
            }
            .store(in: &cancellables)
    }
    
    var isTranscriptionBusy: Bool {
        transcriptionQueue.isProcessing
            || (transcriptionService.isTranscribing && !transcriptionService.isLiveWhisperSessionActive)
    }

    private var shouldUseLiveWhisperHotkeyStreaming: Bool {
        AppPreferences.shared.selectedEngine == "whisper" && AppPreferences.shared.holdToRecord
    }

    var liveTranscriptPreview: String {
        (liveCommittedText + livePreviewText).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func showBusyMessage() {
        state = .busy
        
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.delegate?.didFinishDecoding()
            }
        }
    }
    
    func startRecording() {
        if isTranscriptionBusy {
            showBusyMessage()
            return
        }
        
        if MicrophoneService.shared.isActiveMicrophoneRequiresConnection() {
            state = .connecting
            stopBlinking()
        } else {
            state = .recording
            startBlinking()
        }

        if shouldUseLiveWhisperHotkeyStreaming {
            recorder.startLiveHotkeyCapture { [weak self] samples in
                guard let self = self else { return }
                Task { @MainActor in
                    self.transcriptionService.consumeLiveWhisperSamples(samples)
                }
            }

            Task { [weak self] in
                guard let self = self else { return }

                do {
                    try await self.transcriptionService.startLiveWhisperHotkeySession(settings: Settings())
                } catch {
                    print("Failed to start live Whisper session: \(error)")
                    self.recorder.cancelRecording()
                    await self.transcriptionService.cancelLiveWhisperHotkeySession()
                    await MainActor.run {
                        self.state = .idle
                        self.delegate?.didFinishDecoding()
                    }
                }
            }
            return
        }

        Task.detached { [recorder] in
            recorder.startRecording()
        }
    }
    
    func startDecoding() {
        stopBlinking()
        
        if isTranscriptionBusy && !transcriptionService.isLiveWhisperSessionActive {
            recorder.cancelRecording()
            showBusyMessage()
            return
        }
        
        state = .decoding

        if transcriptionService.isLiveWhisperSessionActive {
            let tempURL = recorder.stopLiveHotkeyCapture()

            Task { [weak self] in
                guard let self = self else { return }

                _ = await self.transcriptionService.finishLiveWhisperHotkeySession()

                if let tempURL {
                    do {
                        let text = try await self.transcriptionService.transcribeAudio(
                            url: tempURL,
                            settings: Settings()
                        )
                        try await self.persistCompletedRecording(from: tempURL, transcription: text)
                    } catch {
                        print("Error finalizing live Whisper audio: \(error)")
                        try? FileManager.default.removeItem(at: tempURL)
                    }
                }

                await MainActor.run {
                    self.delegate?.didFinishDecoding()
                }
            }
            return
        }
        
        if let tempURL = recorder.stopRecording() {
            Task { [weak self] in
                guard let self = self else { return }
                
                do {
                    print("start decoding...")
                    let text = try await transcriptionService.transcribeAudio(url: tempURL, settings: Settings())
                    try await self.persistCompletedRecording(from: tempURL, transcription: text)
                    
                    insertText(text)
                    print("Transcription result: \(text)")
                } catch {
                    print("Error transcribing audio: \(error)")
                    try? FileManager.default.removeItem(at: tempURL)
                }
                
                await MainActor.run {
                    self.delegate?.didFinishDecoding()
                }
            }
        } else {
            
            print("!!! Not found record url !!!")
            
            Task {
                await MainActor.run {
                    self.delegate?.didFinishDecoding()
                }
            }
        }
    }
    
    func insertText(_ text: String) {
        let finalText = Self.applyPostProcessing(text)
        ClipboardUtil.insertText(finalText)
    }
    
    static func applyPostProcessing(_ text: String) -> String {
        guard AppPreferences.shared.addSpaceAfterSentence,
              let lastChar = text.last,
              lastChar.isPunctuation else {
            return text
        }
        return text + " "
    }
    
    private func startBlinking() {
        blinkTimer?.invalidate()
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            // Update UI on the main thread
            Task { @MainActor in
                guard let self = self else { return }
                self.isBlinking.toggle()
            }
        }
    }
    
    private func stopBlinking() {
        blinkTimer?.invalidate()
        blinkTimer = nil
        isBlinking = false
    }

    func cleanup() {
        stopBlinking()
        hideTimer?.invalidate()
        hideTimer = nil
        liveCommittedText = ""
        livePreviewText = ""
        cancellables.removeAll()
    }

    func cancelRecording() {
        hideTimer?.invalidate()
        hideTimer = nil
        if transcriptionService.isLiveWhisperSessionActive {
            Task {
                await self.transcriptionService.cancelLiveWhisperHotkeySession()
            }
        }
        recorder.cancelRecording()
    }

    private func persistCompletedRecording(from tempURL: URL, transcription: String) async throws {
        let timestamp = Date()
        let fileName = "\(Int(timestamp.timeIntervalSince1970)).wav"
        let recordingId = UUID()
        let finalRecording = Recording(
            id: recordingId,
            timestamp: timestamp,
            fileName: fileName,
            transcription: transcription,
            duration: 0,
            status: .completed,
            progress: 1.0,
            sourceFileURL: nil
        )

        try recorder.moveTemporaryRecording(from: tempURL, to: finalRecording.url)

        await MainActor.run {
            self.recordingStore.addRecording(finalRecording)
        }
    }

    @MainActor
    func hideWithAnimation() async {
        await withCheckedContinuation { continuation in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                self.isVisible = false
            } completion: {
                continuation.resume()
            }
        }
    }
}

struct RecordingIndicator: View {
    let isBlinking: Bool
    
    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.red.opacity(0.8),
                        Color.red
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 8, height: 8)
            .shadow(color: .red.opacity(0.5), radius: 4)
            .opacity(isBlinking ? 0.3 : 1.0)
            .animation(.easeInOut(duration: 0.4), value: isBlinking)
    }
}

struct IndicatorWindow: View {
    @ObservedObject var viewModel: IndicatorViewModel
    @Environment(\.colorScheme) private var colorScheme
    
    private var backgroundColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.24)
            : Color.white.opacity(0.24)
    }
    
    var body: some View {

        let rect = RoundedRectangle(cornerRadius: 24)
        
        VStack(spacing: 12) {
            switch viewModel.state {
            case .connecting:
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 24)
                    
                    Text("Connecting...")
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
            case .recording:
                HStack(spacing: 8) {
                    RecordingIndicator(isBlinking: viewModel.isBlinking)
                        .frame(width: 24)
                    
                    Text("Recording...")
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
            case .decoding:
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 24)
                    
                    Text("Transcribing...")
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
            case .busy:
                HStack(spacing: 8) {
                    Image(systemName: "hourglass")
                        .foregroundColor(.orange)
                        .frame(width: 24)
                    
                    Text("Processing...")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.orange)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
            case .idle:
                EmptyView()
            }

            if !viewModel.liveTranscriptPreview.isEmpty {
                Text(viewModel.liveTranscriptPreview)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary.opacity(0.9))
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .frame(minHeight: 36)
        .background {
            rect
                .fill(backgroundColor)
                .background {
                    rect
                        .fill(Material.thinMaterial)
                }
                .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
        }
        .clipShape(rect)
        .frame(width: viewModel.liveTranscriptPreview.isEmpty ? 200 : 280)
        .scaleEffect(viewModel.isVisible ? 1 : 0.5)
        .offset(y: viewModel.isVisible ? 0 : 20)
        .opacity(viewModel.isVisible ? 1 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.isVisible)
        .onAppear {
            viewModel.isVisible = true
        }
    }
}

struct IndicatorWindowPreview: View {
    @StateObject private var recordingVM = {
        let vm = IndicatorViewModel()
//        vm.startRecording()
        return vm
    }()
    
    @StateObject private var decodingVM = {
        let vm = IndicatorViewModel()
        vm.startDecoding()
        return vm
    }()
    
    var body: some View {
        VStack(spacing: 20) {
            IndicatorWindow(viewModel: recordingVM)
            IndicatorWindow(viewModel: decodingVM)
        }
        .padding()
        .frame(height: 200)
        .background(Color(.windowBackgroundColor))
    }
}

#Preview {
    IndicatorWindowPreview()
}
