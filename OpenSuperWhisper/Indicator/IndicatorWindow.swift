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
        TranscriptionService.combineLivePreviewText(
            committedText: liveCommittedText,
            previewText: livePreviewText
        )
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
                            settings: Settings(),
                            preserveDisplayedText: true
                        )
                        try await self.persistCompletedRecording(from: tempURL, transcription: text)
                        self.insertText(text)
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

    private let outerCornerRadius: CGFloat = 28
    private let badgeCornerRadius: CGFloat = 14
    private let transcriptCornerRadius: CGFloat = 22

    private var outerGlassTint: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.07)
            : Color.white.opacity(0.20)
    }

    private var badgeGlassTint: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.11)
            : Color.white.opacity(0.24)
    }

    private var transcriptGlassTint: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.05)
            : Color.white.opacity(0.16)
    }

    private var fallbackFillColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.07)
            : Color.white.opacity(0.30)
    }

    private var fallbackBadgeFillColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.11)
            : Color.white.opacity(0.24)
    }

    private var fallbackInnerFillColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.06)
            : Color.white.opacity(0.18)
    }

    private var highlightStrokeColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.24)
            : Color.white.opacity(0.38)
    }

    private var softStrokeColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.14)
            : Color.white.opacity(0.24)
    }

    private var transcriptStrokeColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.12)
            : Color.white.opacity(0.20)
    }

    private var separatorColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.10)
            : Color.white.opacity(0.16)
    }

    private var shadowColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.26)
            : Color.black.opacity(0.14)
    }

    private var highlightGlowColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.06)
            : Color.white.opacity(0.12)
    }

    private var specularHighlight: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(colorScheme == .dark ? 0.24 : 0.32),
                Color.white.opacity(colorScheme == .dark ? 0.10 : 0.16),
                Color.clear
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var ambientWash: LinearGradient {
        LinearGradient(
            colors: [
                highlightGlowColor,
                Color.clear,
                Color.white.opacity(colorScheme == .dark ? 0.02 : 0.05)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    @ViewBuilder
    private func applyBadgeSurface<Content: View>(to content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular.tint(badgeGlassTint), in: .rect(cornerRadius: badgeCornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: badgeCornerRadius)
                        .strokeBorder(softStrokeColor, lineWidth: 0.6)
                }
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: badgeCornerRadius)
                        .fill(fallbackBadgeFillColor)
                        .background {
                            RoundedRectangle(cornerRadius: badgeCornerRadius)
                                .fill(.regularMaterial)
                        }
                )
                .overlay {
                    RoundedRectangle(cornerRadius: badgeCornerRadius)
                        .strokeBorder(softStrokeColor, lineWidth: 0.6)
                }
        }
    }

    @ViewBuilder
    private func applyOuterSurface<Content: View>(to content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular.tint(outerGlassTint), in: .rect(cornerRadius: outerCornerRadius))
                .background {
                    RoundedRectangle(cornerRadius: outerCornerRadius)
                        .fill(ambientWash)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: outerCornerRadius)
                        .strokeBorder(highlightStrokeColor, lineWidth: 0.75)
                }
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: outerCornerRadius)
                        .fill(specularHighlight)
                        .frame(height: 36)
                        .padding(1)
                        .blur(radius: 1.25)
                        .mask(
                            RoundedRectangle(cornerRadius: outerCornerRadius)
                                .padding(1)
                        )
                }
                .shadow(color: shadowColor, radius: 20, x: 0, y: 10)
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: outerCornerRadius)
                        .fill(fallbackFillColor)
                        .background {
                            RoundedRectangle(cornerRadius: outerCornerRadius)
                                .fill(.ultraThinMaterial)
                        }
                )
                .overlay {
                    RoundedRectangle(cornerRadius: outerCornerRadius)
                        .fill(ambientWash)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: outerCornerRadius)
                        .strokeBorder(highlightStrokeColor, lineWidth: 0.75)
                }
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: outerCornerRadius)
                        .fill(specularHighlight)
                        .frame(height: 34)
                        .padding(1)
                        .blur(radius: 1.5)
                        .mask(
                            RoundedRectangle(cornerRadius: outerCornerRadius)
                                .padding(1)
                        )
                }
                .shadow(color: shadowColor, radius: 16, x: 0, y: 8)
        }
    }

    @ViewBuilder
    private func applyTranscriptSurface<Content: View>(to content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular.tint(transcriptGlassTint), in: .rect(cornerRadius: transcriptCornerRadius))
                .background {
                    RoundedRectangle(cornerRadius: transcriptCornerRadius)
                        .fill(ambientWash)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: transcriptCornerRadius)
                        .strokeBorder(transcriptStrokeColor, lineWidth: 0.6)
                }
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.12))
                        .frame(height: 0.8)
                        .padding(.horizontal, 14)
                        .padding(.top, 1)
                }
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: transcriptCornerRadius)
                        .fill(fallbackInnerFillColor)
                        .background {
                            RoundedRectangle(cornerRadius: transcriptCornerRadius)
                                .fill(.regularMaterial)
                        }
                )
                .overlay {
                    RoundedRectangle(cornerRadius: transcriptCornerRadius)
                        .fill(ambientWash)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: transcriptCornerRadius)
                        .strokeBorder(transcriptStrokeColor, lineWidth: 0.6)
                }
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(Color.white.opacity(colorScheme == .dark ? 0.07 : 0.10))
                        .frame(height: 0.8)
                        .padding(.horizontal, 14)
                        .padding(.top, 1)
                }
        }
    }

    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                GlassEffectContainer(spacing: 12) {
                    applyOuterSurface(to: overlayContent)
                }
            } else {
                applyOuterSurface(to: overlayContent)
            }
        }
        .frame(width: viewModel.liveTranscriptPreview.isEmpty ? 250 : 420)
        .scaleEffect(viewModel.isVisible ? 1 : 0.5)
        .offset(y: viewModel.isVisible ? 0 : 20)
        .opacity(viewModel.isVisible ? 1 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.isVisible)
        .onAppear {
            viewModel.isVisible = true
        }
    }

    private var overlayContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusRow

            if !viewModel.liveTranscriptPreview.isEmpty {
                Rectangle()
                    .fill(separatorColor)
                    .frame(height: 0.75)
                    .frame(maxWidth: .infinity)

                applyTranscriptSurface(to: transcriptSection)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(minHeight: 44)
    }

    @ViewBuilder
    private var statusRow: some View {
        let labelColor = statusUsesAccentColor ? Color.orange : Color.primary

        switch viewModel.state {
        case .connecting:
            HStack(spacing: 12) {
                statusAccessory
                Text("Connecting...")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(labelColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .recording:
            HStack(spacing: 12) {
                statusAccessory
                Text("Recording...")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(labelColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .decoding:
            HStack(spacing: 12) {
                statusAccessory
                Text("Transcribing...")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(labelColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .busy:
            HStack(spacing: 12) {
                statusAccessory
                Text("Processing...")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(labelColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder
    private var statusAccessory: some View {
        applyBadgeSurface(
            to: Group {
                switch viewModel.state {
                case .connecting, .decoding:
                    ProgressView()
                        .controlSize(.small)
                        .tint(.primary.opacity(0.8))
                case .recording:
                    RecordingIndicator(isBlinking: viewModel.isBlinking)
                case .busy:
                    Image(systemName: "hourglass")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.orange)
                case .idle:
                    EmptyView()
                }
            }
            .frame(width: 28, height: 28)
        )
    }

    private var statusUsesAccentColor: Bool {
        viewModel.state == .busy
    }

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.liveTranscriptPreview)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.primary.opacity(0.92))
                .lineSpacing(4)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
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
