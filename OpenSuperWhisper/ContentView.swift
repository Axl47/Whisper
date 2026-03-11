import AppKit
import AVFoundation
import Combine
import KeyboardShortcuts
import SwiftUI

@MainActor
final class ContentViewModel: ObservableObject {
    @Published var state: RecordingState = .idle
    @Published var isBlinking = false
    @Published var recorder: AudioRecorder = .shared
    @Published var transcriptionService = TranscriptionService.shared
    @Published var transcriptionQueue = TranscriptionQueue.shared
    @Published var recordingStore = RecordingStore.shared
    @Published var recordings: [Recording] = []
    @Published var isLoadingMore = false
    @Published var canLoadMore = true
    @Published var recordingDuration: TimeInterval = 0
    @Published var microphoneService = MicrophoneService.shared
    @Published var shouldClearSearch = false

    private var currentPage = 0
    private let pageSize = 100
    private var currentSearchQuery = ""
    private var blinkTimer: Timer?
    private var recordingStartTime: Date?
    private var durationTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let liveRecordingCoordinator: LiveRecordingCoordinator

    init(liveRecordingCoordinator: LiveRecordingCoordinator? = nil) {
        self.liveRecordingCoordinator = liveRecordingCoordinator ?? .shared

        recorder.$isConnecting
            .receive(on: RunLoop.main)
            .sink { [weak self] isConnecting in
                guard let self else { return }
                if isConnecting && self.state != .decoding {
                    self.state = .connecting
                    self.stopBlinking()
                    self.stopDurationTimer()
                    self.recordingDuration = 0
                }
            }
            .store(in: &cancellables)

        recorder.$isRecording
            .receive(on: RunLoop.main)
            .sink { [weak self] isRecording in
                guard let self else { return }
                if isRecording && self.state != .decoding {
                    self.state = .recording
                    self.startBlinking()
                    self.startDurationTimerIfNeeded()
                } else if !isRecording && self.state == .recording {
                    self.state = .idle
                    self.stopBlinking()
                    self.stopDurationTimer()
                    self.recordingDuration = 0
                }
            }
            .store(in: &cancellables)
    }

    func loadInitialData() {
        currentSearchQuery = ""
        currentPage = 0
        canLoadMore = true
        recordings = []
        loadMore()
    }

    func loadMore() {
        guard !isLoadingMore && canLoadMore else { return }
        isLoadingMore = true

        let page = currentPage
        let limit = pageSize
        let query = currentSearchQuery
        let offset = page * limit

        Task {
            let newRecordings: [Recording]
            if query.isEmpty {
                newRecordings = try await recordingStore.fetchRecordings(limit: limit, offset: offset)
            } else {
                newRecordings = await recordingStore.searchRecordingsAsync(query: query, limit: limit, offset: offset)
            }

            await MainActor.run {
                defer {
                    self.isLoadingMore = false
                }

                guard self.currentSearchQuery == query else {
                    return
                }

                if page == 0 {
                    self.recordings = newRecordings
                } else {
                    self.recordings.append(contentsOf: newRecordings)
                }

                if newRecordings.count < limit {
                    self.canLoadMore = false
                } else {
                    self.currentPage += 1
                }
            }
        }
    }

    func search(query: String) {
        currentSearchQuery = query
        currentPage = 0
        canLoadMore = true
        recordings = []
        loadMore()
    }

    func handleProgressUpdate(
        id: UUID,
        transcription: String?,
        progress: Float,
        status: RecordingStatus,
        isRegeneration: Bool?
    ) {
        if let index = recordings.firstIndex(where: { $0.id == id }) {
            if let transcription {
                recordings[index].transcription = transcription
            }
            recordings[index].progress = progress
            recordings[index].status = status
            if let isRegeneration {
                recordings[index].isRegeneration = isRegeneration
            }
        }
    }

    func deleteRecording(_ recording: Recording) {
        recordingStore.deleteRecording(recording)
        if let index = recordings.firstIndex(where: { $0.id == recording.id }) {
            recordings.remove(at: index)
        }
    }

    func deleteAllRecordings() {
        recordingStore.deleteAllRecordings()
        recordings.removeAll()
    }

    var isRecording: Bool {
        recorder.isRecording
    }

    func startRecording() {
        if microphoneService.isActiveMicrophoneRequiresConnection() {
            state = .connecting
            stopBlinking()
            stopDurationTimer()
            recordingDuration = 0
        } else {
            state = .recording
            startBlinking()
            recordingStartTime = Date()
            recordingDuration = 0
            startDurationTimerIfNeeded()
        }

        Task.detached { [recorder] in
            recorder.startRecording()
        }
    }

    func startDecoding() {
        state = .decoding
        stopBlinking()
        stopDurationTimer()

        IndicatorWindowManager.shared.hide()

        if let tempURL = recorder.stopRecording() {
            Task { [weak self] in
                guard let self else { return }

                do {
                    let duration = await MainActor.run { self.recordingDuration }
                    let result = try await self.liveRecordingCoordinator.finalizeRecording(
                        tempURL: tempURL,
                        duration: duration,
                        settings: Settings(),
                        deliveryTarget: .historyOnly
                    )

                    await MainActor.run {
                        if !self.currentSearchQuery.isEmpty {
                            self.shouldClearSearch = true
                            self.currentSearchQuery = ""
                        }
                        self.recordings.insert(result.recording, at: 0)
                    }
                } catch {
                    print("Error transcribing audio: \(error)")
                    try? FileManager.default.removeItem(at: tempURL)
                }

                await MainActor.run {
                    self.state = .idle
                    self.recordingDuration = 0
                }
            }
        } else {
            state = .idle
            recordingDuration = 0
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
        recordingStartTime = nil
    }

    private func startDurationTimerIfNeeded() {
        guard durationTimer == nil else { return }
        if recordingStartTime == nil {
            recordingStartTime = Date()
            recordingDuration = 0
        }
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            let startTime = Date()
            Task { @MainActor in
                if let recordingStartTime = self.recordingStartTime {
                    self.recordingDuration = startTime.timeIntervalSince(recordingStartTime)
                }
            }
        }
        RunLoop.main.add(durationTimer!, forMode: .common)
    }

    private func startBlinking() {
        blinkTimer?.invalidate()
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.isBlinking.toggle()
            }
        }
        RunLoop.main.add(blinkTimer!, forMode: .common)
    }

    private func stopBlinking() {
        blinkTimer?.invalidate()
        blinkTimer = nil
        isBlinking = false
    }
}

struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()
    @StateObject private var permissionsManager = PermissionsManager()
    @Environment(\.colorScheme) private var colorScheme
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 16) {
            MainWindowSearchBar(
                searchText: $searchText,
                onChange: performSearch,
                onClear: clearSearch
            )

            if arePermissionsGranted {
                MainRecordingsListSection(
                    viewModel: viewModel,
                    searchQuery: debouncedSearchText,
                    selectedRecordingID: nil
                )

                MainRecorderFooterSection(
                    viewModel: viewModel,
                    onOpenSettings: openSettingsWindow
                )
            } else {
                PermissionsView(permissionsManager: permissionsManager)
                    .padding(.bottom, 12)
            }
        }
        .padding(16)
        .frame(minWidth: 400, idealWidth: 400)
        .background(ThemePalette.windowBackground(colorScheme))
        .overlay {
            if viewModel.transcriptionService.isLoading && arePermissionsGranted {
                LoadingOverlayView()
            }
        }
        .fileDropHandler()
        .onAppear {
            viewModel.loadInitialData()
        }
        .onReceive(NotificationCenter.default.publisher(for: RecordingStore.recordingProgressDidUpdateNotification)) { notification in
            guard let userInfo = notification.userInfo,
                  let id = userInfo["id"] as? UUID,
                  let progress = userInfo["progress"] as? Float,
                  let status = userInfo["status"] as? RecordingStatus else { return }

            viewModel.handleProgressUpdate(
                id: id,
                transcription: userInfo["transcription"] as? String,
                progress: progress,
                status: status,
                isRegeneration: userInfo["isRegeneration"] as? Bool
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: RecordingStore.recordingsDidUpdateNotification)) { _ in
            viewModel.loadInitialData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            openSettingsWindow()
        }
        .onChange(of: viewModel.shouldClearSearch) { _, shouldClear in
            if shouldClear {
                clearSearch()
                viewModel.shouldClearSearch = false
            }
        }
        .onDisappear {
            searchTask?.cancel()
        }
    }

    private var arePermissionsGranted: Bool {
        permissionsManager.isMicrophonePermissionGranted
            && permissionsManager.isAccessibilityPermissionGranted
    }

    private func performSearch(_ query: String) {
        searchTask?.cancel()

        guard !query.isEmpty else {
            debouncedSearchText = ""
            viewModel.search(query: "")
            return
        }

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                debouncedSearchText = query
                viewModel.search(query: query)
            }
        }
    }

    private func clearSearch() {
        searchText = ""
        debouncedSearchText = ""
        searchTask?.cancel()
        viewModel.search(query: "")
    }
}

struct MainWindowSearchBar: View {
    @Binding var searchText: String
    let onChange: (String) -> Void
    let onClear: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search in transcriptions", text: $searchText)
                .textFieldStyle(.plain)
                .onChange(of: searchText) { _, newValue in
                    onChange(newValue)
                }

            if !searchText.isEmpty {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .imageScale(.medium)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(ThemePalette.panelSurface(colorScheme))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(ThemePalette.panelBorder(colorScheme), lineWidth: 1)
        }
        .cornerRadius(20)
    }
}

struct MainRecordingsListSection: View {
    @ObservedObject var viewModel: ContentViewModel
    let searchQuery: String
    let selectedRecordingID: UUID?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                if viewModel.recordings.isEmpty {
                    MainRecordingsEmptyState(searchQuery: searchQuery)
                        .frame(maxWidth: .infinity)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.recordings) { recording in
                            RecordingRow(
                                recording: recording,
                                searchQuery: searchQuery,
                                isSelected: recording.id == selectedRecordingID,
                                onDelete: {
                                    viewModel.deleteRecording(recording)
                                },
                                onRegenerate: {
                                    Task {
                                        await TranscriptionQueue.shared.requeueRecording(recording)
                                    }
                                }
                            )
                            .id(recording.id)
                            .onAppear {
                                if recording.id == viewModel.recordings.last?.id {
                                    viewModel.loadMore()
                                }
                            }
                        }

                        if viewModel.isLoadingMore {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 6)
                }
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                ThemePalette.windowBackground(colorScheme).opacity(1),
                                ThemePalette.windowBackground(colorScheme).opacity(0)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 20)
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.recordings.count)
            .animation(.easeInOut(duration: 0.2), value: searchQuery.isEmpty)
            .onChange(of: selectedRecordingID) { _, id in
                guard let id else { return }
                withAnimation(.easeInOut(duration: 0.18)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }
}

struct MainRecordingsEmptyState: View {
    let searchQuery: String

    var body: some View {
        VStack(spacing: 16) {
            if !searchQuery.isEmpty {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary)
                    .padding(.top, 40)

                Text("No results found")
                    .font(.headline)
                    .foregroundColor(.secondary)

                Text("Try different search terms")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            } else {
                Image(systemName: "waveform.badge.mic")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary)
                    .padding(.top, 40)

                Text("No recordings yet")
                    .font(.headline)
                    .foregroundColor(.secondary)

                Text("Start recording or drop an audio file to build your history.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                let shortcut = currentShortcutDescription()
                if !shortcut.isEmpty {
                    VStack(spacing: 8) {
                        Text("Pro Tip")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.secondary)

                        HStack(spacing: 6) {
                            Text("Press")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text(shortcut)
                                .font(.system(size: 15, weight: .medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.16))
                                .cornerRadius(7)
                            Text("anywhere to show the mini recorder")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 12)
                }
            }
        }
        .padding(.bottom, 24)
    }
}

struct MainRecorderFooterSection: View {
    @ObservedObject var viewModel: ContentViewModel
    let onOpenSettings: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(spacing: 16) {
            Button(action: {
                if viewModel.isRecording {
                    viewModel.startDecoding()
                } else {
                    viewModel.startRecording()
                }
            }) {
                if viewModel.state == .decoding || viewModel.state == .connecting {
                    ProgressView()
                        .frame(width: 48, height: 48)
                } else {
                    MainRecordButton(isRecording: viewModel.isRecording)
                }
            }
            .buttonStyle(.plain)
            .disabled(
                viewModel.transcriptionService.isLoading
                    || viewModel.transcriptionService.isTranscribing
                    || viewModel.transcriptionQueue.isProcessing
                    || viewModel.state == .decoding
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.isRecording)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.state)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(currentShortcutDescription())
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("to show mini recorder")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, 4)

                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.doc.fill")
                            .foregroundColor(.secondary)
                            .imageScale(.medium)
                        Text("Drop audio files here to transcribe")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, 4)
                }

                Spacer()

                HStack(spacing: 12) {
                    MicrophonePickerIconView(microphoneService: viewModel.microphoneService)

                    if !viewModel.recordings.isEmpty {
                        Button(action: {
                            showDeleteConfirmation = true
                        }) {
                            footerIcon(symbolName: "trash")
                        }
                        .buttonStyle(.plain)
                        .help("Delete all recordings")
                        .confirmationDialog(
                            "Delete All Recordings",
                            isPresented: $showDeleteConfirmation,
                            titleVisibility: .visible
                        ) {
                            Button("Delete All", role: .destructive) {
                                viewModel.deleteAllRecordings()
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("Are you sure you want to delete all recordings? This action cannot be undone.")
                        }
                        .interactiveDismissDisabled()
                    }

                    Button(action: onOpenSettings) {
                        footerIcon(symbolName: "gear")
                    }
                    .buttonStyle(.plain)
                    .help("Settings")
                }
            }
        }
    }

    private func footerIcon(symbolName: String) -> some View {
        Image(systemName: symbolName)
            .font(.title3)
            .foregroundColor(.secondary)
            .frame(width: 32, height: 32)
            .background(ThemePalette.panelSurface(colorScheme))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(ThemePalette.panelBorder(colorScheme), lineWidth: 1)
            }
            .cornerRadius(8)
    }
}

struct LoadingOverlayView: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                Text("Loading Whisper Model...")
                    .foregroundColor(.white)
                    .font(.headline)
            }
        }
        .ignoresSafeArea()
    }
}

struct PermissionsView: View {
    @ObservedObject var permissionsManager: PermissionsManager

    var body: some View {
        VStack(spacing: 20) {
            Text("Required Permissions")
                .font(.title)
                .padding(.top, 8)

            PermissionRow(
                isGranted: permissionsManager.isMicrophonePermissionGranted,
                title: "Microphone Access",
                description: "Required for audio recording",
                action: {
                    permissionsManager.requestMicrophonePermissionOrOpenSystemPreferences()
                }
            )

            PermissionRow(
                isGranted: permissionsManager.isAccessibilityPermissionGranted,
                title: "Accessibility Access",
                description: "Required for global keyboard shortcuts",
                action: { permissionsManager.openSystemPreferences(for: .accessibility) }
            )

            Spacer(minLength: 0)
        }
        .padding()
    }
}

struct PermissionRow: View {
    let isGranted: Bool
    let title: String
    let description: String
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(isGranted ? .green : .red)

                Text(title)
                    .font(.headline)

                Spacer()

                if !isGranted {
                    Button("Grant Access") {
                        action()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Text(description)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(ThemePalette.panelSurface(colorScheme))
        .cornerRadius(10)
    }
}

struct RecordingRow: View {
    let recording: Recording
    let searchQuery: String
    let isSelected: Bool
    let onDelete: () -> Void
    let onRegenerate: () -> Void

    @StateObject private var audioRecorder = AudioRecorder.shared
    @State private var showTranscription = false
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    private var isPlaying: Bool {
        audioRecorder.isPlaying && audioRecorder.currentlyPlayingURL == recording.url
    }

    private var isPending: Bool {
        recording.status == .pending || recording.status == .converting || recording.status == .transcribing
    }

    private var isRegenerating: Bool {
        recording.isRegeneration && isPending
    }

    private var statusText: String {
        switch recording.status {
        case .pending:
            return "In queue..."
        case .converting:
            return "Converting..."
        case .transcribing:
            return "Transcribing..."
        case .completed:
            return ""
        case .failed:
            return "Failed"
        }
    }

    private var displayText: String {
        if recording.transcription.isEmpty
            || recording.transcription == "Starting transcription..."
            || recording.transcription == "In queue..." {
            return ""
        }
        return recording.transcription
    }

    private var isWorkflow: Bool {
        recording.deliveryKind == .workflow
    }

    private var workflowFailureMessage: String? {
        guard recording.deliveryKind == .workflow,
              recording.workflowExecutionStatus == .failed else {
            return nil
        }
        return recording.workflowExecutionMessage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isPending && !isRegenerating {
                VStack(alignment: .leading, spacing: 4) {
                    if let sourceFileName = recording.sourceFileName {
                        Text(sourceFileName)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    HStack(spacing: 6) {
                        if recording.status == .pending {
                            Image(systemName: "clock")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            ZStack {
                                Circle()
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 2)

                                Circle()
                                    .trim(from: 0, to: CGFloat(recording.progress))
                                    .stroke(Color.secondary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                    .animation(.linear(duration: 0.1), value: recording.progress)
                            }
                            .frame(width: 16, height: 16)

                            Text("\(Int(recording.progress * 100))%")
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.secondary)
                                .contentTransition(.numericText())
                                .animation(.linear(duration: 0.1), value: recording.progress)
                        }

                        Text(statusText)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }

            if recording.status == .failed {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                        Text("Transcription failed")
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    if !recording.transcription.isEmpty {
                        Text(recording.transcription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, isPending && !isRegenerating ? 4 : 8)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if isWorkflow {
                        HStack(spacing: 8) {
                            Text("Workflow")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.purple)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.purple.opacity(0.12))
                                .clipShape(Capsule())

                            if let workflowName = recording.workflowName, !workflowName.isEmpty {
                                Text(workflowName)
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    if let workflowFailureMessage {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                            Text(workflowFailureMessage)
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }

                    if !displayText.isEmpty {
                        ZStack(alignment: .topLeading) {
                            TranscriptionView(
                                transcribedText: displayText,
                                searchQuery: searchQuery,
                                isExpanded: $showTranscription
                            )

                            if isRegenerating {
                                ShimmerOverlay()
                                    .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                            }
                        }
                    } else if !isPending && !isWorkflow {
                        Text("No speech detected")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, isWorkflow ? 12 : 4)
                .padding(.top, isPending && !isRegenerating ? 4 : 8)
            }

            Divider()
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(recording.timestamp, style: .date)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text(recording.timestamp, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if isRegenerating {
                    Spacer()
                        .frame(width: 2)
                    HStack(spacing: 6) {
                        if recording.status == .pending {
                            Image(systemName: "clock")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            ZStack {
                                Circle()
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 2)

                                Circle()
                                    .trim(from: 0, to: CGFloat(recording.progress))
                                    .stroke(Color.secondary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                    .animation(.linear(duration: 0.1), value: recording.progress)
                            }
                            .frame(width: 16, height: 16)

                            Text("\(Int(recording.progress * 100))%")
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.secondary)
                                .contentTransition(.numericText())
                                .animation(.linear(duration: 0.1), value: recording.progress)
                        }

                        Text(statusText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .transition(.opacity)
                }

                Spacer()

                HStack(spacing: 16) {
                    if !isPending && recording.status != .failed && (isHovered || isPlaying) {
                        Button(action: {
                            if isPlaying {
                                audioRecorder.stopPlaying()
                            } else {
                                audioRecorder.playRecording(url: recording.url)
                            }
                        }) {
                            Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(isPlaying ? .red : ThemePalette.iconAccent(colorScheme))
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity)

                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(recording.transcription, forType: .string)
                        }) {
                            Image(systemName: "doc.on.doc.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Copy entire text")
                        .transition(.opacity)
                    }

                    if (recording.status == .completed || recording.status == .failed) && isHovered {
                        Button(action: onRegenerate) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 18))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Regenerate transcription")
                        .transition(.opacity)
                    }

                    if isHovered || isPlaying || (isPending && !isRegenerating) || recording.status == .failed {
                        Button(action: {
                            if isPlaying {
                                audioRecorder.stopPlaying()
                            }
                            onDelete()
                        }) {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: isHovered)
                .animation(.easeInOut(duration: 0.2), value: isPlaying)
                .animation(.easeInOut(duration: 0.2), value: isRegenerating)
            }
            .animation(.easeInOut(duration: 0.2), value: isRegenerating)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .background(ThemePalette.cardBackground(colorScheme))
        }
        .background(ThemePalette.cardBackground(colorScheme))
        .cornerRadius(12)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isSelected ? Color.accentColor.opacity(0.36) : ThemePalette.cardBorder(colorScheme),
                    lineWidth: isSelected ? 1.2 : 1
                )
        }
        .shadow(
            color: isSelected ? Color.accentColor.opacity(0.10) : .clear,
            radius: 10,
            x: 0,
            y: 4
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .padding(.vertical, 4)
    }
}

struct ShimmerOverlay: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.clear,
                                    Color.white.opacity(0.4),
                                    Color.clear
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .offset(x: -geometry.size.width + (phase * geometry.size.width * 2))
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }
}

struct TranscriptionView: View {
    let transcribedText: String
    let searchQuery: String
    @Binding var isExpanded: Bool
    @Environment(\.colorScheme) private var colorScheme

    @State private var highlightedAttributedString: AttributedString?
    @State private var computeTask: Task<Void, Never>?

    private var hasMoreLines: Bool {
        !transcribedText.isEmpty && transcribedText.count > 150
    }

    private var highlightedText: Text {
        guard !searchQuery.isEmpty else {
            return Text(transcribedText)
        }
        if let highlightedAttributedString {
            return Text(highlightedAttributedString)
        }
        return Text(transcribedText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if isExpanded {
                    ScrollView {
                        highlightedText
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 200)
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            if hasMoreLines {
                                isExpanded.toggle()
                            }
                        }
                    )
                } else if hasMoreLines {
                    Button(action: { isExpanded.toggle() }) {
                        highlightedText
                            .font(.body)
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                } else {
                    highlightedText
                        .font(.body)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .padding(8)

            if hasMoreLines {
                Button(action: { isExpanded.toggle() }) {
                    HStack(spacing: 4) {
                        Text(isExpanded ? "Show less" : "Show more")
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    }
                    .foregroundColor(ThemePalette.linkText(colorScheme))
                    .font(.footnote)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .onAppear {
            computeHighlighting()
        }
        .onChange(of: searchQuery) { _, _ in
            computeHighlighting()
        }
        .onChange(of: transcribedText) { _, _ in
            computeHighlighting()
        }
        .onDisappear {
            computeTask?.cancel()
        }
    }

    private func computeHighlighting() {
        computeTask?.cancel()

        guard !searchQuery.isEmpty else {
            highlightedAttributedString = nil
            return
        }

        let text = transcribedText
        let query = searchQuery

        computeTask = Task.detached(priority: .userInitiated) {
            var highlightedString = AttributedString(text)
            let searchOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

            var searchStartIndex = text.startIndex
            while let range = text.range(of: query, options: searchOptions, range: searchStartIndex..<text.endIndex) {
                guard !Task.isCancelled else { return }
                if let attributedRange = Range(range, in: highlightedString) {
                    highlightedString[attributedRange].backgroundColor = .yellow
                    highlightedString[attributedRange].foregroundColor = .black
                }
                searchStartIndex = range.upperBound
            }

            guard !Task.isCancelled else { return }
            let completedHighlightedString = highlightedString

            await MainActor.run {
                self.highlightedAttributedString = completedHighlightedString
            }
        }
    }
}

struct MicrophonePickerIconView: View {
    @ObservedObject var microphoneService: MicrophoneService
    @State private var showMenu = false
    @Environment(\.colorScheme) private var colorScheme

    private var builtInMicrophones: [MicrophoneService.AudioDevice] {
        microphoneService.availableMicrophones.filter(\.isBuiltIn)
    }

    private var externalMicrophones: [MicrophoneService.AudioDevice] {
        microphoneService.availableMicrophones.filter { !$0.isBuiltIn }
    }

    var body: some View {
        Button(action: {
            showMenu.toggle()
        }) {
            Image(systemName: microphoneService.availableMicrophones.isEmpty ? "mic.slash" : "mic.fill")
                .font(.title3)
                .foregroundColor(.secondary)
                .frame(width: 32, height: 32)
                .background(ThemePalette.panelSurface(colorScheme))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(ThemePalette.panelBorder(colorScheme), lineWidth: 1)
                }
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .help(microphoneService.currentMicrophone?.displayName ?? "Select microphone")
        .popover(isPresented: $showMenu, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 0) {
                if microphoneService.availableMicrophones.isEmpty {
                    Text("No microphones available")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    ForEach(builtInMicrophones) { microphone in
                        microphoneMenuRow(microphone)
                    }

                    if !builtInMicrophones.isEmpty && !externalMicrophones.isEmpty {
                        Divider()
                            .padding(.vertical, 4)
                    }

                    ForEach(externalMicrophones) { microphone in
                        microphoneMenuRow(microphone)
                    }
                }
            }
            .frame(minWidth: 220)
            .padding(.vertical, 8)
        }
    }

    private func microphoneMenuRow(_ microphone: MicrophoneService.AudioDevice) -> some View {
        Button(action: {
            microphoneService.selectMicrophone(microphone)
            showMenu = false
        }) {
            HStack {
                Text(microphone.displayName)
                Spacer()
                if let current = microphoneService.currentMicrophone,
                   current.id == microphone.id {
                    Image(systemName: "checkmark")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct MainRecordButton: View {
    let isRecording: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var buttonColor: Color {
        ThemePalette.recordButtonBase(colorScheme)
    }

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        isRecording ? Color.red.opacity(0.8) : buttonColor.opacity(0.8),
                        isRecording ? Color.red : buttonColor.opacity(0.9)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 48, height: 48)
            .shadow(
                color: isRecording ? .red.opacity(0.5) : buttonColor.opacity(0.3),
                radius: 12,
                x: 0,
                y: 0
            )
            .overlay {
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                isRecording ? .red.opacity(0.6) : buttonColor.opacity(0.6),
                                isRecording ? .red.opacity(0.3) : buttonColor.opacity(0.3)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .scaleEffect(isRecording ? 0.9 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isRecording)
    }
}

enum ThemePalette {
    static func windowBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(NSColor.underPageBackgroundColor)
            : .white
    }

    static func panelSurface(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.gray.opacity(0.1)
            : Color(red: 0.95, green: 0.96, blue: 0.98)
    }

    static func panelBorder(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.gray.opacity(0.2)
            : Color(red: 0.86, green: 0.88, blue: 0.92)
    }

    static func cardBackground(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(NSColor.controlBackgroundColor)
            : Color.white
    }

    static func cardBorder(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(NSColor.separatorColor)
            : Color(red: 0.86, green: 0.88, blue: 0.92)
    }

    static func recordButtonBase(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? .white
            : Color(red: 0.35, green: 0.60, blue: 0.92)
    }

    static func iconAccent(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .accentColor : .primary
    }

    static func linkText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? .blue : .primary
    }
}

@MainActor
private func currentShortcutDescription() -> String {
    let modifierKey = ModifierKey(rawValue: AppPreferences.shared.modifierOnlyHotkey) ?? .none
    if modifierKey != .none {
        return modifierKey.shortSymbol
    } else if let shortcut = KeyboardShortcuts.getShortcut(for: .toggleRecord) {
        return shortcut.description
    }
    return ""
}

@MainActor
private func openSettingsWindow() {
    guard let appDelegate = NSApp.delegate as? AppDelegate else {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        return
    }
    appDelegate.openSettingsWindow()
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
