import AppKit
import Carbon
import Combine
import Foundation
import KeyboardShortcuts
import SwiftUI
import FluidAudio

class SettingsViewModel: ObservableObject {
    @Published var selectedEngine: String {
        didSet {
            AppPreferences.shared.selectedEngine = selectedEngine
            if selectedEngine == "whisper" {
                loadAvailableModels()
            } else {
                initializeFluidAudioModels()
            }
            Task { @MainActor in
                TranscriptionService.shared.reloadEngine()
            }
        }
    }
    
    @Published var fluidAudioModelVersion: String {
        didSet {
            AppPreferences.shared.fluidAudioModelVersion = fluidAudioModelVersion
            if selectedEngine == "fluidaudio" {
                Task { @MainActor in
                    TranscriptionService.shared.reloadEngine()
                }
            }
            initializeFluidAudioModels()
        }
    }
    
    @Published var selectedModelURL: URL? {
        didSet {
            if let url = selectedModelURL {
                AppPreferences.shared.selectedWhisperModelPath = url.path
            }
        }
    }

    @Published var availableModels: [URL] = []
    
    @Published var downloadableModels: [SettingsDownloadableModel] = []
    @Published var downloadableFluidAudioModels: [SettingsFluidAudioModel] = []
    @Published var isDownloading: Bool = false
    @Published var downloadProgress: Double = 0.0
    @Published var downloadingModelName: String?
    private var downloadTask: Task<Void, Error>?
    
    @Published var selectedLanguage: String {
        didSet {
            AppPreferences.shared.whisperLanguage = selectedLanguage
            NotificationCenter.default.post(name: .appPreferencesLanguageChanged, object: nil)
        }
    }

    @Published var translateToEnglish: Bool {
        didSet {
            AppPreferences.shared.translateToEnglish = translateToEnglish
        }
    }

    @Published var suppressBlankAudio: Bool {
        didSet {
            AppPreferences.shared.suppressBlankAudio = suppressBlankAudio
        }
    }

    @Published var showTimestamps: Bool {
        didSet {
            AppPreferences.shared.showTimestamps = showTimestamps
        }
    }
    
    @Published var temperature: Double {
        didSet {
            AppPreferences.shared.temperature = temperature
        }
    }

    @Published var noSpeechThreshold: Double {
        didSet {
            AppPreferences.shared.noSpeechThreshold = noSpeechThreshold
        }
    }

    @Published var initialPrompt: String {
        didSet {
            AppPreferences.shared.initialPrompt = initialPrompt
        }
    }

    @Published var whisperBoostedWords: String {
        didSet {
            AppPreferences.shared.whisperBoostedWords = whisperBoostedWords
        }
    }

    @Published var useBeamSearch: Bool {
        didSet {
            AppPreferences.shared.useBeamSearch = useBeamSearch
        }
    }

    @Published var beamSize: Int {
        didSet {
            AppPreferences.shared.beamSize = beamSize
        }
    }

    @Published var debugMode: Bool {
        didSet {
            AppPreferences.shared.debugMode = debugMode
        }
    }
    
    @Published var playSoundOnRecordStart: Bool {
        didSet {
            AppPreferences.shared.playSoundOnRecordStart = playSoundOnRecordStart
        }
    }
    
    @Published var useAsianAutocorrect: Bool {
        didSet {
            AppPreferences.shared.useAsianAutocorrect = useAsianAutocorrect
        }
    }
    
    @Published var modifierOnlyHotkey: ModifierKey {
        didSet {
            AppPreferences.shared.modifierOnlyHotkey = modifierOnlyHotkey.rawValue
            NotificationCenter.default.post(name: .hotkeySettingsChanged, object: nil)
        }
    }
    
    @Published var holdToRecord: Bool {
        didSet {
            AppPreferences.shared.holdToRecord = holdToRecord
        }
    }
    
    @Published var addSpaceAfterSentence: Bool {
        didSet {
            AppPreferences.shared.addSpaceAfterSentence = addSpaceAfterSentence
        }
    }

    @Published var voiceWorkflowsEnabled: Bool {
        didSet {
            AppPreferences.shared.voiceWorkflowsEnabled = voiceWorkflowsEnabled
        }
    }

    @Published var workflows: [VoiceWorkflow]
    
    init() {
        let prefs = AppPreferences.shared
        self.selectedEngine = prefs.selectedEngine
        self.fluidAudioModelVersion = prefs.fluidAudioModelVersion
        self.selectedLanguage = prefs.whisperLanguage
        self.translateToEnglish = prefs.translateToEnglish
        self.suppressBlankAudio = prefs.suppressBlankAudio
        self.showTimestamps = prefs.showTimestamps
        self.temperature = prefs.temperature
        self.noSpeechThreshold = prefs.noSpeechThreshold
        self.initialPrompt = prefs.initialPrompt
        self.whisperBoostedWords = prefs.whisperBoostedWords
        self.useBeamSearch = prefs.useBeamSearch
        self.beamSize = prefs.beamSize
        self.debugMode = prefs.debugMode
        self.playSoundOnRecordStart = prefs.playSoundOnRecordStart
        self.useAsianAutocorrect = prefs.useAsianAutocorrect
        self.modifierOnlyHotkey = ModifierKey(rawValue: prefs.modifierOnlyHotkey) ?? .none
        self.holdToRecord = prefs.holdToRecord
        self.addSpaceAfterSentence = prefs.addSpaceAfterSentence
        self.voiceWorkflowsEnabled = prefs.voiceWorkflowsEnabled
        self.workflows = prefs.voiceWorkflows
        
        if let savedPath = prefs.selectedWhisperModelPath ?? prefs.selectedModelPath {
            self.selectedModelURL = URL(fileURLWithPath: savedPath)
        }
        loadAvailableModels()
        initializeDownloadableModels()
        initializeFluidAudioModels()
    }
    
    func initializeFluidAudioModels() {
        downloadableFluidAudioModels = SettingsFluidAudioModels.availableModels.map { model in
            var updatedModel = model
            updatedModel.isDownloaded = isFluidAudioModelDownloaded(version: model.version)
            return updatedModel
        }
    }
    
    func isFluidAudioModelDownloaded(version: String) -> Bool {
        let asrVersion: AsrModelVersion = version == "v2" ? .v2 : .v3
        
        // Используем правильный путь к кэшу согласно документации:
        // ~/Library/Application Support/FluidAudio/Models/<version-folder>/
        let cacheDirectory = AsrModels.defaultCacheDirectory(for: asrVersion)
        
        // Проверяем наличие всех необходимых файлов модели
        return AsrModels.modelsExist(at: cacheDirectory, version: asrVersion)
    }
    
    func initializeDownloadableModels() {
        let modelManager = WhisperModelManager.shared
        downloadableModels = SettingsDownloadableModels.availableModels.map { model in
            var updatedModel = model
            let filename = model.url.lastPathComponent
            updatedModel.isDownloaded = modelManager.isModelDownloaded(name: filename)
            return updatedModel
        }
    }
    
    func loadAvailableModels() {
        availableModels = WhisperModelManager.shared.getAvailableModels()
        if selectedModelURL == nil {
            selectedModelURL = availableModels.first
        }
        initializeDownloadableModels()
    }

    func addWorkflow(_ workflow: VoiceWorkflow) {
        workflows.append(workflow)
        saveWorkflows()
    }

    func updateWorkflow(_ workflow: VoiceWorkflow) {
        guard let index = workflows.firstIndex(where: { $0.id == workflow.id }) else {
            return
        }
        workflows[index] = workflow
        saveWorkflows()
    }

    func deleteWorkflows(atOffsets offsets: IndexSet) {
        workflows.remove(atOffsets: offsets)
        saveWorkflows()
    }

    func deleteWorkflow(id: UUID) {
        workflows.removeAll { $0.id == id }
        saveWorkflows()
    }

    func saveWorkflows() {
        AppPreferences.shared.voiceWorkflows = workflows
    }

    func validationErrors(for workflow: VoiceWorkflow) -> [VoiceWorkflowValidationError] {
        VoiceWorkflowValidator.validate(workflow: workflow, duringSaveAgainst: workflows)
    }
    
    @MainActor
    func downloadModel(_ model: SettingsDownloadableModel) async throws {
        guard !isDownloading else { return }
        
        isDownloading = true
        downloadingModelName = model.name
        downloadProgress = 0.0
        
        downloadTask = Task {
            do {
                let filename = model.url.lastPathComponent
                
                try await WhisperModelManager.shared.downloadModel(url: model.url, name: filename) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self = self, !Task.isCancelled else { return }
                        guard let task = self.downloadTask, !task.isCancelled else { return }
                        
                        self.downloadProgress = progress
                        if let index = self.downloadableModels.firstIndex(where: { $0.name == model.name }) {
                            self.downloadableModels[index].downloadProgress = progress
                            if progress >= 1.0 {
                                self.downloadableModels[index].isDownloaded = true
                            }
                        }
                    }
                }
                
                guard !Task.isCancelled else {
                    await MainActor.run {
                        self.isDownloading = false
                        self.downloadingModelName = nil
                        self.downloadProgress = 0.0
                        if let index = self.downloadableModels.firstIndex(where: { $0.name == model.name }) {
                            self.downloadableModels[index].downloadProgress = 0.0
                        }
                    }
                    return
                }
                
                await MainActor.run {
                    if let index = downloadableModels.firstIndex(where: { $0.name == model.name }) {
                        downloadableModels[index].isDownloaded = true
                        downloadableModels[index].downloadProgress = 0.0
                    }
                    loadAvailableModels()
                    let modelPath = WhisperModelManager.shared.modelsDirectory.appendingPathComponent(filename).path
                    selectedModelURL = URL(fileURLWithPath: modelPath)
                    isDownloading = false
                    downloadingModelName = nil
                    downloadProgress = 0.0
                    
                    Task { @MainActor in
                        TranscriptionService.shared.reloadModel(with: modelPath)
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    isDownloading = false
                    downloadingModelName = nil
                    downloadProgress = 0.0
                    if let index = downloadableModels.firstIndex(where: { $0.name == model.name }) {
                        downloadableModels[index].downloadProgress = 0.0
                    }
                }
            } catch {
                await MainActor.run {
                    isDownloading = false
                    downloadingModelName = nil
                    downloadProgress = 0.0
                    if let index = downloadableModels.firstIndex(where: { $0.name == model.name }) {
                        downloadableModels[index].downloadProgress = 0.0
                    }
                }
                throw error
            }
        }
        
        try await downloadTask?.value
    }
    
    func cancelDownload() {
        downloadTask?.cancel()
        if let modelName = downloadingModelName {
            if selectedEngine == "whisper", let model = downloadableModels.first(where: { $0.name == modelName }) {
                let filename = model.url.lastPathComponent
                WhisperModelManager.shared.cancelDownload(name: filename)
            }
            // Reset progress for the downloading model
            if let index = downloadableModels.firstIndex(where: { $0.name == modelName }) {
                downloadableModels[index].downloadProgress = 0.0
            }
            if let index = downloadableFluidAudioModels.firstIndex(where: { $0.name == modelName }) {
                downloadableFluidAudioModels[index].downloadProgress = 0.0
            }
        }
        isDownloading = false
        downloadingModelName = nil
        downloadProgress = 0.0
    }
    
    @MainActor
    func downloadFluidAudioModel(_ model: SettingsFluidAudioModel) async throws {
        guard !isDownloading else { return }
        
        isDownloading = true
        downloadingModelName = model.name
        downloadProgress = 0.0
        
        if let index = downloadableFluidAudioModels.firstIndex(where: { $0.id == model.id }) {
            downloadableFluidAudioModels[index].downloadProgress = 0.0
        }
        
        var wasCancelled = false
        
        downloadTask = Task {
            do {
                let version: AsrModelVersion = model.version == "v2" ? .v2 : .v3
                
                guard !Task.isCancelled else {
                    await MainActor.run {
                        self.isDownloading = false
                        self.downloadingModelName = nil
                        self.downloadProgress = 0.0
                        if let index = self.downloadableFluidAudioModels.firstIndex(where: { $0.id == model.id }) {
                            self.downloadableFluidAudioModels[index].downloadProgress = 0.0
                        }
                    }
                    throw CancellationError()
                }
                
                let models = try await AsrModels.downloadAndLoad(version: version)
                
                guard !Task.isCancelled else {
                    await MainActor.run {
                        self.isDownloading = false
                        self.downloadingModelName = nil
                        self.downloadProgress = 0.0
                        if let index = self.downloadableFluidAudioModels.firstIndex(where: { $0.id == model.id }) {
                            self.downloadableFluidAudioModels[index].downloadProgress = 0.0
                        }
                    }
                    throw CancellationError()
                }
                
                let manager = AsrManager(config: .default)
                try await manager.initialize(models: models)
                
                await MainActor.run {
                    if let index = downloadableFluidAudioModels.firstIndex(where: { $0.id == model.id }) {
                        downloadableFluidAudioModels[index].isDownloaded = true
                        downloadableFluidAudioModels[index].downloadProgress = 1.0
                    }
                    fluidAudioModelVersion = model.version
                    isDownloading = false
                    downloadingModelName = nil
                    downloadProgress = 1.0
                    
                    Task { @MainActor in
                        TranscriptionService.shared.reloadEngine()
                    }
                }
            } catch is CancellationError {
                wasCancelled = true
                await MainActor.run {
                    isDownloading = false
                    downloadingModelName = nil
                    downloadProgress = 0.0
                    if let index = downloadableFluidAudioModels.firstIndex(where: { $0.id == model.id }) {
                        downloadableFluidAudioModels[index].downloadProgress = 0.0
                    }
                }
                // Don't re-throw CancellationError - it's a manual cancellation
            } catch {
                // Check if we were cancelled before the error occurred
                if Task.isCancelled {
                    wasCancelled = true
                    await MainActor.run {
                        isDownloading = false
                        downloadingModelName = nil
                        downloadProgress = 0.0
                        if let index = downloadableFluidAudioModels.firstIndex(where: { $0.id == model.id }) {
                            downloadableFluidAudioModels[index].downloadProgress = 0.0
                        }
                    }
                } else {
                    await MainActor.run {
                        isDownloading = false
                        downloadingModelName = nil
                        downloadProgress = 0.0
                        if let index = downloadableFluidAudioModels.firstIndex(where: { $0.id == model.id }) {
                            downloadableFluidAudioModels[index].downloadProgress = 0.0
                        }
                    }
                    throw error
                }
            }
        }
        
        // Handle cancellation gracefully - don't throw if cancelled
        do {
            try await downloadTask?.value
        } catch is CancellationError {
            // Already handled in catch block above, just consume the error
            wasCancelled = true
        } catch {
            // If we were cancelled, don't throw
            if !wasCancelled {
                throw error
            }
        }
    }
    
    @MainActor
    func downloadFluidAudioModel() async throws {
        let versionString = AppPreferences.shared.fluidAudioModelVersion
        if let model = downloadableFluidAudioModels.first(where: { $0.version == versionString }) {
            try await downloadFluidAudioModel(model)
        }
    }
}

struct SettingsDownloadableModel: Identifiable {
    let id = UUID()
    let name: String
    var isDownloaded: Bool
    let url: URL
    let size: Int
    let description: String
    var downloadProgress: Double = 0.0

    var sizeString: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: Int64(size) * 1000000)
    }

    init(name: String, isDownloaded: Bool, url: URL, size: Int, description: String) {
        self.name = name
        self.isDownloaded = isDownloaded
        self.url = url
        self.size = size
        self.description = description
    }
}

struct SettingsDownloadableModels {
    static let availableModels = [
        SettingsDownloadableModel(
            name: "Turbo V3 large",
            isDownloaded: false,
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin?download=true")!,
            size: 1624,
            description: "High accuracy, best quality"
        ),
        SettingsDownloadableModel(
            name: "Turbo V3 medium",
            isDownloaded: false,
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q8_0.bin?download=true")!,
            size: 874,
            description: "Balanced speed and accuracy"
        ),
        SettingsDownloadableModel(
            name: "Turbo V3 small",
            isDownloaded: false,
            url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin?download=true")!,
            size: 574,
            description: "Fastest processing"
        )
    ]
}

struct Settings: Sendable {
    static let asianLanguages: Set<String> = ["zh", "ja", "ko"]
    
    var selectedLanguage: String
    var translateToEnglish: Bool
    var suppressBlankAudio: Bool
    var showTimestamps: Bool
    var temperature: Double
    var noSpeechThreshold: Double
    var initialPrompt: String
    var whisperBoostedWords: String
    var useBeamSearch: Bool
    var beamSize: Int
    var useAsianAutocorrect: Bool
    
    var isAsianLanguage: Bool {
        Settings.asianLanguages.contains(selectedLanguage)
    }
    
    var shouldApplyAsianAutocorrect: Bool {
        isAsianLanguage && useAsianAutocorrect
    }
    
    init() {
        let prefs = AppPreferences.shared
        self.selectedLanguage = prefs.whisperLanguage
        self.translateToEnglish = prefs.translateToEnglish
        self.suppressBlankAudio = prefs.suppressBlankAudio
        self.showTimestamps = prefs.showTimestamps
        self.temperature = prefs.temperature
        self.noSpeechThreshold = prefs.noSpeechThreshold
        self.initialPrompt = prefs.initialPrompt
        self.whisperBoostedWords = prefs.whisperBoostedWords
        self.useBeamSearch = prefs.useBeamSearch
        self.beamSize = prefs.beamSize
        self.useAsianAutocorrect = prefs.useAsianAutocorrect
    }
}

struct SettingsView: View {
    let onDone: (() -> Void)?

    @StateObject private var viewModel = SettingsViewModel()
    @Environment(\.dismiss) var dismiss
    @State private var isRecordingNewShortcut = false
    @State private var selectedTab = 0
    @State private var previousModelURL: URL?
    @State private var workflowEditorDraft: VoiceWorkflowDraft?

    init(onDone: (() -> Void)? = nil) {
        self.onDone = onDone
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {

             // Shortcut Settings
            shortcutSettings
                .tabItem {
                    Label("Shortcuts", systemImage: "command")
                }
                .tag(0)
            // Model Settings
            modelSettings
                .tabItem {
                    Label("Model", systemImage: "cpu")
                }
                .tag(1)
            
            // Transcription Settings
            transcriptionSettings
                .tabItem {
                    Label("Transcription", systemImage: "text.bubble")
                }
                .tag(2)
            
            // Advanced Settings
            advancedSettings
                .tabItem {
                    Label("Advanced", systemImage: "gear")
                }
                .tag(3)

            workflowsSettings
                .tabItem {
                    Label("Workflows", systemImage: "bolt.horizontal.circle")
                }
                .tag(4)
            }
        .padding()
        .frame(width: 620)
        .background(Color(.windowBackgroundColor))
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("Done") {
                    if viewModel.selectedEngine == "whisper" {
                        if viewModel.selectedModelURL != previousModelURL, let modelPath = viewModel.selectedModelURL?.path {
                            TranscriptionService.shared.reloadModel(with: modelPath)
                        }
                    }
                    if let onDone {
                        onDone()
                    } else {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                
                Spacer()
                
                Link(destination: URL(string: "https://github.com/Starmel/OpenSuperWhisper")!) {
                    HStack(spacing: 4) {
                        Image(systemName: "star")
                            .font(.system(size: 10))
                        Text("GitHub")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(.windowBackgroundColor))
        }
        .onAppear {
            previousModelURL = viewModel.selectedModelURL
            if viewModel.selectedEngine == "fluidaudio" {
                viewModel.initializeFluidAudioModels()
            }
        }
        .onChange(of: viewModel.selectedEngine) { _, newEngine in
            if newEngine == "fluidaudio" {
                viewModel.initializeFluidAudioModels()
            }
        }
        .onChange(of: viewModel.fluidAudioModelVersion) { _, _ in
            Task { @MainActor in
                TranscriptionService.shared.reloadEngine()
            }
        }
        .onChange(of: viewModel.selectedModelURL) { _, newURL in
            if viewModel.selectedEngine == "whisper", let modelPath = newURL?.path {
                Task { @MainActor in
                    TranscriptionService.shared.reloadModel(with: modelPath)
                }
            }
        }
        .sheet(item: $workflowEditorDraft) { draft in
            VoiceWorkflowEditorSheet(
                draft: draft,
                existingWorkflows: viewModel.workflows
            ) { savedWorkflow in
                if viewModel.workflows.contains(where: { $0.id == savedWorkflow.id }) {
                    viewModel.updateWorkflow(savedWorkflow)
                } else {
                    viewModel.addWorkflow(savedWorkflow)
                }
                workflowEditorDraft = nil
            } onCancel: {
                workflowEditorDraft = nil
            }
        }
    }
    
    private var modelSettings: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Speech Recognition Engine")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Picker("Engine", selection: $viewModel.selectedEngine) {
                        Text("Parakeet").tag("fluidaudio")
                        Text("Whisper").tag("whisper")
                    }
                    .pickerStyle(.segmented)
                    .padding(.bottom, 8)
                    
                    if viewModel.selectedEngine == "whisper" {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Whisper Model")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Text("Download Models")
                                .font(.headline)
                                .foregroundColor(.primary)
                                .padding(.top, 8)
                            
                            ScrollView {
                                VStack(spacing: 12) {
                                    ForEach($viewModel.downloadableModels) { $model in
                                        ModelDownloadItemView(model: $model, viewModel: viewModel)
                                    }
                                }
                            }
                            .frame(maxHeight: 200)
                            
                            if viewModel.isDownloading {
                                VStack(spacing: 8) {
                                    HStack {
                                        if viewModel.downloadProgress > 0 {
                                            ProgressView(value: viewModel.downloadProgress)
                                                .progressViewStyle(LinearProgressViewStyle())
                                        } else {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle())
                                        }
                                        
                                        Spacer()
                                        
                                        Button("Cancel") {
                                            viewModel.cancelDownload()
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                    
                                    if let downloadingName = viewModel.downloadingModelName {
                                        Text("Downloading: \(downloadingName)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.top, 8)
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Models Directory:")
                                        .font(.subheadline)
                                    Button(action: {
                                        NSWorkspace.shared.open(WhisperModelManager.shared.modelsDirectory)
                                    }) {
                                        Label("Open Folder", systemImage: "folder")
                                            .font(.subheadline)
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Open models directory")
                                }
                                Text(WhisperModelManager.shared.modelsDirectory.path)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .textSelection(.enabled)
                                    .padding(8)
                                    .background(Color(.textBackgroundColor).opacity(0.5))
                                    .cornerRadius(6)
                            }
                            .padding(.top, 8)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Parakeet Model")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Text("Download Models")
                                .font(.headline)
                                .foregroundColor(.primary)
                                .padding(.top, 8)
                            
                            ScrollView {
                                VStack(spacing: 12) {
                                    ForEach($viewModel.downloadableFluidAudioModels) { $model in
                                        FluidAudioModelDownloadItemView(model: $model, viewModel: viewModel)
                                    }
                                }
                            }
                            .frame(maxHeight: 200)
                            
                            if viewModel.isDownloading {
                                VStack(spacing: 8) {
                                    HStack {
                                        if viewModel.downloadProgress > 0 {
                                            ProgressView(value: viewModel.downloadProgress)
                                                .progressViewStyle(LinearProgressViewStyle())
                                        } else {
                                            ProgressView()
                                                .progressViewStyle(CircularProgressViewStyle())
                                        }
                                        
                                        Spacer()
                                        
                                        Button("Cancel") {
                                            viewModel.cancelDownload()
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                    
                                    if let downloadingName = viewModel.downloadingModelName {
                                        Text("Downloading: \(downloadingName)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.top, 8)
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Models Directory:")
                                        .font(.subheadline)
                                    Button(action: {
                                        let cacheDir = AsrModels.defaultCacheDirectory(for: .v3)
                                        let parentDir = cacheDir.deletingLastPathComponent()
                                        NSWorkspace.shared.open(parentDir)
                                    }) {
                                        Label("Open Folder", systemImage: "folder")
                                            .font(.subheadline)
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Open models directory")
                                }
                                Text(AsrModels.defaultCacheDirectory(for: .v3).deletingLastPathComponent().path)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .textSelection(.enabled)
                                    .padding(8)
                                    .background(Color(.textBackgroundColor).opacity(0.5))
                                    .cornerRadius(6)
                            }
                            .padding(.top, 8)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)
            }
        }
        .padding()
    }
    
    private var transcriptionSettings: some View {
        Form {
            VStack(spacing: 20) {
                // Language Settings
                VStack(alignment: .leading, spacing: 16) {
                    Text("Language Settings")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Transcription Language")
                            .font(.subheadline)
                        
                        Picker("Language", selection: $viewModel.selectedLanguage) {
                            ForEach(LanguageUtil.availableLanguages, id: \.self) { code in
                                Text(LanguageUtil.languageNames[code] ?? code)
                                    .tag(code)
                            }
                        }
                        .pickerStyle(.menu)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        HStack {
                            Text("Translate to English")
                                .font(.subheadline)
                            Spacer()
                            Toggle("", isOn: $viewModel.translateToEnglish)
                                .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                                .labelsHidden()
                        }
                        .padding(.top, 4)
                        
                        if Settings.asianLanguages.contains(viewModel.selectedLanguage) {
                            HStack {
                                Text("Use Asian Autocorrect")
                                    .font(.subheadline)
                                Spacer()
                                Toggle("", isOn: $viewModel.useAsianAutocorrect)
                                    .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                                    .labelsHidden()
                            }
                            .padding(.top, 4)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)
                
                // Output Options
                VStack(alignment: .leading, spacing: 16) {
                    Text("Output Options")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Show Timestamps")
                                .font(.subheadline)
                            Spacer()
                            Toggle("", isOn: $viewModel.showTimestamps)
                                .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                                .labelsHidden()
                        }
                        
                        HStack {
                            Text("Suppress Blank Audio")
                                .font(.subheadline)
                            Spacer()
                            Toggle("", isOn: $viewModel.suppressBlankAudio)
                                .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                                .labelsHidden()
                        }
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Add Space After Sentence")
                                    .font(.subheadline)
                                Text("Appends a space when transcription ends with punctuation")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $viewModel.addSpaceAfterSentence)
                                .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                                .labelsHidden()
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)
                
                // Initial Prompt
                VStack(alignment: .leading, spacing: 16) {
                    Text("Initial Prompt")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        TextEditor(text: $viewModel.initialPrompt)
                            .frame(height: 60)
                            .padding(6)
                            .background(Color(.textBackgroundColor))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                        
                        Text("Optional text to guide the model's transcription")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)

                if viewModel.selectedEngine == "whisper" {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Boosted Words")
                            .font(.headline)
                            .foregroundColor(.primary)

                        VStack(alignment: .leading, spacing: 8) {
                            TextEditor(text: $viewModel.whisperBoostedWords)
                                .frame(height: 96)
                                .padding(6)
                                .background(Color(.textBackgroundColor))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )

                            Text("One preferred word or phrase per line.")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text("Biases Whisper toward preferred spellings for names and jargon. Does not train the model or permanently learn pronunciation.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.controlBackgroundColor).opacity(0.3))
                    .cornerRadius(12)
                }
                
                // Transcriptions Directory
                VStack(alignment: .leading, spacing: 16) {
                    Text("Transcriptions Directory")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Directory:")
                                .font(.subheadline)
                            Spacer()
                            Button(action: {
                                NSWorkspace.shared.open(Recording.recordingsDirectory)
                            }) {
                                Label("Open Folder", systemImage: "folder")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.borderless)
                            .help("Open transcriptions directory")
                        }
                        
                        Text(Recording.recordingsDirectory.path)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.textBackgroundColor).opacity(0.5))
                            .cornerRadius(6)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)
            }
            .padding()
        }
    }
    
    private var advancedSettings: some View {
        Form {
            VStack(spacing: 20) {
                // Decoding Strategy
                VStack(alignment: .leading, spacing: 16) {
                    Text("Decoding Strategy")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Use Beam Search")
                                .font(.subheadline)
                            Spacer()
                            Toggle("", isOn: $viewModel.useBeamSearch)
                                .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                                .labelsHidden()
                                .help("Beam search can provide better results but is slower")
                        }
                        
                        if viewModel.useBeamSearch {
                            HStack {
                                Text("Beam Size:")
                                    .font(.subheadline)
                                Spacer()
                                Stepper("\(viewModel.beamSize)", value: $viewModel.beamSize, in: 1...10)
                                    .help("Number of beams to use in beam search")
                                    .frame(width: 120)
                            }
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)
                
                // Model Parameters
                VStack(alignment: .leading, spacing: 16) {
                    Text("Model Parameters")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Temperature:")
                                    .font(.subheadline)
                                Spacer()
                                Text(String(format: "%.2f", viewModel.temperature))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            Slider(value: $viewModel.temperature, in: 0.0...1.0, step: 0.1)
                                .help("Higher values make the output more random")
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("No Speech Threshold:")
                                    .font(.subheadline)
                                Spacer()
                                Text(String(format: "%.2f", viewModel.noSpeechThreshold))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            Slider(value: $viewModel.noSpeechThreshold, in: 0.0...1.0, step: 0.1)
                                .help("Threshold for detecting speech vs. silence")
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)
                
                // Debug Options
                VStack(alignment: .leading, spacing: 16) {
                    Text("Debug Options")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    HStack {
                        Text("Debug Mode")
                            .font(.subheadline)
                        Spacer()
                        Toggle("", isOn: $viewModel.debugMode)
                            .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                            .labelsHidden()
                            .help("Enable additional logging and debugging information")
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)
            }
        }
        .padding()
    }

    private var workflowsSettings: some View {
        ScrollView {
            VStack(spacing: 20) {
                WorkflowSettingsCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Voice Workflows")
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text("Workflows run only for completed live microphone recordings. Imported files and queued transcriptions always stay as normal transcripts.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Enable Voice Workflows")
                                    .font(.subheadline.weight(.medium))
                                Text("When enabled, the app checks live transcripts for workflow aliases before paste delivery.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $viewModel.voiceWorkflowsEnabled)
                                .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                                .labelsHidden()
                        }
                    }
                }

                WorkflowSettingsCard {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Configured Workflows")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Text("Aliases are matched from the start of the final transcript. The remaining text becomes the `{text}` payload.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Button {
                                workflowEditorDraft = VoiceWorkflowDraft()
                            } label: {
                                Label("Add Workflow", systemImage: "plus")
                            }
                            .workflowActionButtonStyle()
                        }

                        if viewModel.workflows.isEmpty {
                            Text("No workflows configured yet.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 12)
                        } else {
                            VStack(spacing: 12) {
                                ForEach(viewModel.workflows) { workflow in
                                    WorkflowSummaryCard(
                                        workflow: workflow,
                                        onEdit: {
                                            workflowEditorDraft = VoiceWorkflowDraft(workflow: workflow)
                                        },
                                        onDelete: {
                                            viewModel.deleteWorkflow(id: workflow.id)
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }
    
    private var useModifierKey: Bool {
        viewModel.modifierOnlyHotkey != .none
    }
    
    private var shortcutSettings: some View {
        Form {
            VStack(spacing: 20) {
                // Recording Trigger
                VStack(alignment: .leading, spacing: 16) {
                    Text("Recording Trigger")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Picker("", selection: Binding(
                            get: { useModifierKey },
                            set: { newValue in
                                if !newValue {
                                    viewModel.modifierOnlyHotkey = .none
                                } else if viewModel.modifierOnlyHotkey == .none {
                                    viewModel.modifierOnlyHotkey = .leftCommand
                                }
                            }
                        )) {
                            Text("Key Combination").tag(false)
                            Text("Single Modifier Key").tag(true)
                        }
                        .pickerStyle(.segmented)
                        
                        if useModifierKey {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Modifier Key")
                                        .font(.subheadline)
                                    Spacer()
                                    Picker("", selection: $viewModel.modifierOnlyHotkey) {
                                        ForEach(ModifierKey.allCases.filter { $0 != .none }) { key in
                                            Text(key.displayName).tag(key)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(width: 200)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color(.textBackgroundColor).opacity(0.5))
                                .cornerRadius(8)
                                
                                Text("One-tap to toggle recording")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Shortcut")
                                        .font(.subheadline)
                                    Spacer()
                                    KeyboardShortcuts.Recorder("", name: .toggleRecord)
                                        .frame(width: 150)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color(.textBackgroundColor).opacity(0.5))
                                .cornerRadius(8)
                                
                                if isRecordingNewShortcut {
                                    Text("Press your new shortcut combination...")
                                        .foregroundColor(.secondary)
                                        .font(.subheadline)
                                }
                            }
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)
                
                // Recording Behavior
                VStack(alignment: .leading, spacing: 16) {
                    Text("Recording Behavior")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Hold to Record")
                                    .font(.subheadline)
                                Text("Hold the shortcut to record, release to stop. Press Command while holding to lock hands-free until the shortcut is pressed again.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $viewModel.holdToRecord)
                                .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                                .labelsHidden()
                        }
                        
                        HStack {
                            Text("Play sound when recording starts")
                                .font(.subheadline)
                            Spacer()
                            Toggle("", isOn: $viewModel.playSoundOnRecordStart)
                                .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
                                .labelsHidden()
                                .help("Play a notification sound when recording begins")
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.controlBackgroundColor).opacity(0.3))
                .cornerRadius(12)
            }
            .padding()
        }
    }
}

struct SettingsFluidAudioModel: Identifiable {
    let id = UUID()
    let name: String
    let version: String
    var isDownloaded: Bool
    let description: String
    var downloadProgress: Double = 0.0
}

struct SettingsFluidAudioModels {
    static let availableModels = [
        SettingsFluidAudioModel(
            name: "Parakeet v3",
            version: "v3",
            isDownloaded: false,
            description: "Multilingual, 25 languages"
        ),
        SettingsFluidAudioModel(
            name: "Parakeet v2",
            version: "v2",
            isDownloaded: false,
            description: "English-only, higher recall"
        )
    ]
}

enum OnboardingModelType {
    case whisper(url: URL, size: Int)
    case parakeet(version: String)
}

struct OnboardingUnifiedModel: Identifiable {
    let id = UUID()
    let name: String
    var isDownloaded: Bool
    let description: String
    let type: OnboardingModelType
    var downloadProgress: Double = 0.0
}

struct OnboardingUnifiedModels {
    static let availableModels = [
        OnboardingUnifiedModel(
            name: "Whisper V3 Large",
            isDownloaded: false,
            description: "High accuracy, best quality",
            type: .whisper(
                url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin?download=true")!,
                size: 1624
            )
        ),
        OnboardingUnifiedModel(
            name: "Parakeet v3",
            isDownloaded: false,
            description: "Fastest processing and accurate",
            type: .parakeet(version: "v3")
        ),
        OnboardingUnifiedModel(
            name: "Parakeet v2",
            isDownloaded: false,
            description: "Fastest processing and English-only, higher recall",
            type: .parakeet(version: "v2")
        ),
        OnboardingUnifiedModel(
            name: "Whisper Medium",
            isDownloaded: false,
            description: "Balanced speed and accuracy",
            type: .whisper(
                url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q8_0.bin?download=true")!,
                size: 874
            )
        ),
        OnboardingUnifiedModel(
            name: "Whisper Small",
            isDownloaded: false,
            description: "Very fast processing",
            type: .whisper(
                url: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin?download=true")!,
                size: 574
            )
        )
    ]
}

struct FluidAudioModelDownloadItemView: View {
    @Binding var model: SettingsFluidAudioModel
    @ObservedObject var viewModel: SettingsViewModel
    @State private var showError = false
    @State private var errorMessage = ""
    
    var isSelected: Bool {
        viewModel.fluidAudioModelVersion == model.version
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(model.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    if model.isDownloaded {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(.blue)
                            .imageScale(.small)
                    }
                }
                
                Text(model.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if viewModel.isDownloading && viewModel.downloadingModelName == model.name {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(0.7)
                        .padding(.top, 4)
                } else if model.downloadProgress > 0 && model.downloadProgress < 1 {
                    ProgressView(value: model.downloadProgress)
                        .progressViewStyle(LinearProgressViewStyle())
                        .frame(height: 6)
                        .padding(.top, 4)
                }
            }
            
            Spacer()
            
            if viewModel.isDownloading && viewModel.downloadingModelName == model.name {
                Button("Cancel") {
                    viewModel.cancelDownload()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else if model.isDownloaded {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .imageScale(.large)
                } else {
                    Button(action: {
                        viewModel.fluidAudioModelVersion = model.version
                    }) {
                        Text("Select")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            } else {
                Button(action: {
                    Task {
                        do {
                            try await viewModel.downloadFluidAudioModel(model)
                        } catch is CancellationError {
                            // Don't show error for manual cancellation
                        } catch {
                            errorMessage = error.localizedDescription
                            showError = true
                        }
                    }
                }) {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.isDownloading)
            }
        }
        .padding(12)
        .background(isSelected ? Color(.controlBackgroundColor).opacity(0.7) : Color(.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onTapGesture {
            if model.isDownloaded && !isSelected {
                viewModel.fluidAudioModelVersion = model.version
            }
        }
        .alert("Download Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
}

struct ModelDownloadItemView: View {
    @Binding var model: SettingsDownloadableModel
    @ObservedObject var viewModel: SettingsViewModel
    @State private var showError = false
    @State private var errorMessage = ""
    
    var isSelected: Bool {
        if let selectedURL = viewModel.selectedModelURL {
            let filename = model.url.lastPathComponent
            return selectedURL.lastPathComponent == filename
        }
        return false
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(model.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    if model.isDownloaded {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(.blue)
                            .imageScale(.small)
                    }
                }
                
                Text(model.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if model.downloadProgress > 0 && model.downloadProgress < 1 {
                    ProgressView(value: model.downloadProgress)
                        .progressViewStyle(LinearProgressViewStyle())
                        .frame(height: 6)
                        .padding(.top, 4)
                }
            }
            
            Spacer()
            
            if viewModel.isDownloading && viewModel.downloadingModelName == model.name {
                Button("Cancel") {
                    viewModel.cancelDownload()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else if model.isDownloaded {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .imageScale(.large)
                } else {
                    Button(action: {
                        let modelPath = WhisperModelManager.shared.modelsDirectory.appendingPathComponent(model.url.lastPathComponent).path
                        viewModel.selectedModelURL = URL(fileURLWithPath: modelPath)
                    }) {
                        Text("Select")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            } else {
                Button(action: {
                    Task {
                        do {
                            try await viewModel.downloadModel(model)
                        } catch is CancellationError {
                            // Don't show error for manual cancellation
                        } catch {
                            errorMessage = error.localizedDescription
                            showError = true
                        }
                    }
                }) {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.isDownloading)
            }
        }
        .padding(12)
        .background(isSelected ? Color(.controlBackgroundColor).opacity(0.7) : Color(.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
        .contentShape(Rectangle())
        .onTapGesture {
            if model.isDownloaded && !isSelected {
                let modelPath = WhisperModelManager.shared.modelsDirectory.appendingPathComponent(model.url.lastPathComponent).path
                viewModel.selectedModelURL = URL(fileURLWithPath: modelPath)
            }
        }
        .alert("Download Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
}

private struct VoiceWorkflowDraft: Identifiable {
    let id: UUID
    var name: String
    var isEnabled: Bool
    var aliases: [String]
    var launchMode: VoiceWorkflowLaunchMode
    var executablePath: String
    var arguments: [String]
    var shellCommand: String
    var accentColorHex: String?

    init() {
        self.id = UUID()
        self.name = ""
        self.isEnabled = true
        self.aliases = [""]
        self.launchMode = .executable
        self.executablePath = ""
        self.arguments = ["{text}"]
        self.shellCommand = #"printf '%s\n' "$OPENSUPERWHISPER_WORKFLOW_TEXT""#
        self.accentColorHex = nil
    }

    init(workflow: VoiceWorkflow) {
        self.id = workflow.id
        self.name = workflow.name
        self.isEnabled = workflow.isEnabled
        self.aliases = workflow.aliases.isEmpty ? [""] : workflow.aliases
        self.launchMode = workflow.launchMode
        self.executablePath = workflow.executablePath
        self.arguments = workflow.arguments.isEmpty ? ["{text}"] : workflow.arguments
        self.shellCommand = workflow.shellCommand
        self.accentColorHex = workflow.accentColorHex
    }

    func workflow(accentColorHex: String?) -> VoiceWorkflow {
        VoiceWorkflow(
            id: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            isEnabled: isEnabled,
            aliases: aliases.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) },
            launchMode: launchMode,
            executablePath: executablePath.trimmingCharacters(in: .whitespacesAndNewlines),
            arguments: arguments,
            shellCommand: shellCommand.trimmingCharacters(in: .whitespacesAndNewlines),
            accentColorHex: accentColorHex
        )
    }
}

private struct WorkflowSettingsCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        Group {
            if #available(macOS 26.0, *) {
                GlassEffectContainer(spacing: 12) {
                    content
                        .padding(18)
                        .glassEffect(.regular.tint(Color.white.opacity(0.18)), in: .rect(cornerRadius: 22))
                        .overlay {
                            RoundedRectangle(cornerRadius: 22)
                                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.75)
                        }
                }
            } else {
                content
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 22)
                            .fill(Color(.controlBackgroundColor).opacity(0.42))
                            .background {
                                RoundedRectangle(cornerRadius: 22)
                                    .fill(.ultraThinMaterial)
                            }
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 22)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75)
                    }
            }
        }
    }
}

private struct WorkflowSummaryCard: View {
    let workflow: VoiceWorkflow
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var accentColor: Color? {
        workflow.accentColor
    }

    var body: some View {
        WorkflowSettingsCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(workflow.name.isEmpty ? "Untitled Workflow" : workflow.name)
                                .font(.headline)
                            if !workflow.isEnabled {
                                Text("Disabled")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.secondary.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                            if let accentColor {
                                Circle()
                                    .fill(accentColor)
                                    .frame(width: 10, height: 10)
                            }
                        }

                        Text(
                            workflow.launchMode == .shell
                                ? "Shell Command"
                                : (workflow.executablePath.isEmpty ? "No executable selected" : URL(fileURLWithPath: workflow.executablePath).lastPathComponent)
                        )
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 10) {
                        Button("Edit", action: onEdit)
                            .workflowActionButtonStyle(prominent: true)
                        Button("Delete", role: .destructive, action: onDelete)
                            .workflowActionButtonStyle()
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Aliases")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)

                    Text(workflow.aliases.joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundColor(.primary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(workflow.launchMode == .shell ? "Shell Command" : "Arguments")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    Text(
                        workflow.launchMode == .shell
                            ? workflow.shellCommand
                            : workflow.arguments.joined(separator: " ")
                    )
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

private struct VoiceWorkflowEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: VoiceWorkflowDraft
    @State private var accentColorEnabled: Bool
    @State private var accentColor: Color

    let existingWorkflows: [VoiceWorkflow]
    let onSave: (VoiceWorkflow) -> Void
    let onCancel: () -> Void

    init(
        draft: VoiceWorkflowDraft,
        existingWorkflows: [VoiceWorkflow],
        onSave: @escaping (VoiceWorkflow) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _draft = State(initialValue: draft)
        let initialColor = draft.accentColorHex.flatMap(Color.init(workflowHex:)) ?? .accentColor
        _accentColor = State(initialValue: initialColor)
        _accentColorEnabled = State(initialValue: draft.accentColorHex != nil)
        self.existingWorkflows = existingWorkflows
        self.onSave = onSave
        self.onCancel = onCancel
    }

    private var workflowForValidation: VoiceWorkflow {
        draft.workflow(accentColorHex: accentColorEnabled ? accentColor.workflowHexString() : nil)
    }

    private var validationErrors: [VoiceWorkflowValidationError] {
        VoiceWorkflowValidator.validate(workflow: workflowForValidation, duringSaveAgainst: existingWorkflows)
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Text(draft.name.isEmpty ? "New Workflow" : draft.name)
                    .font(.title3.weight(.semibold))
                Spacer()
            }

            ScrollView {
                VStack(spacing: 16) {
                    WorkflowSettingsCard {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("General")
                                    .font(.headline)
                                Spacer()
                                Toggle("Enabled", isOn: $draft.isEnabled)
                                    .toggleStyle(.switch)
                            }

                            TextField("Workflow Name", text: $draft.name)

                            Picker("Runner", selection: $draft.launchMode) {
                                ForEach(VoiceWorkflowLaunchMode.allCases, id: \.self) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)

                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Popup Accent")
                                        .font(.subheadline.weight(.medium))
                                    Spacer()
                                    Toggle("Use Accent", isOn: $accentColorEnabled)
                                        .toggleStyle(.switch)
                                }

                                if accentColorEnabled {
                                    ColorPicker("Accent Color", selection: $accentColor, supportsOpacity: true)
                                }
                            }
                        }
                    }

                    WorkflowSettingsCard {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("Aliases")
                                    .font(.headline)
                                Spacer()
                                Button {
                                    draft.aliases.append("")
                                } label: {
                                    Label("Add Alias", systemImage: "plus")
                                }
                                .workflowActionButtonStyle()
                            }

                            ForEach(Array(draft.aliases.indices), id: \.self) { index in
                                HStack {
                                    TextField("Alias", text: Binding(
                                        get: { draft.aliases[index] },
                                        set: { draft.aliases[index] = $0 }
                                    ))
                                    Button {
                                        if draft.aliases.count > 1 {
                                            draft.aliases.remove(at: index)
                                        } else {
                                            draft.aliases[index] = ""
                                        }
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    if draft.launchMode == .executable {
                        WorkflowSettingsCard {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Text("Executable")
                                        .font(.headline)
                                    Spacer()
                                    Button("Choose…") {
                                        chooseExecutable()
                                    }
                                    .workflowActionButtonStyle()
                                }

                                TextField("/absolute/path/to/executable", text: $draft.executablePath)
                                    .textSelection(.enabled)
                            }
                        }

                        WorkflowSettingsCard {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Text("Arguments")
                                        .font(.headline)
                                    Spacer()
                                    Button {
                                        draft.arguments.append("")
                                    } label: {
                                        Label("Add Argument", systemImage: "plus")
                                    }
                                    .workflowActionButtonStyle()
                                }

                                ForEach(Array(draft.arguments.indices), id: \.self) { index in
                                    HStack {
                                        TextField("Argument", text: Binding(
                                            get: { draft.arguments[index] },
                                            set: { draft.arguments[index] = $0 }
                                        ))
                                        Button {
                                            if draft.arguments.count > 1 {
                                                draft.arguments.remove(at: index)
                                            } else {
                                                draft.arguments[index] = ""
                                            }
                                        } label: {
                                            Image(systemName: "minus.circle.fill")
                                                .foregroundColor(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    } else {
                        WorkflowSettingsCard {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Shell Command")
                                    .font(.headline)

                                TextEditor(text: $draft.shellCommand)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(minHeight: 120)
                                    .padding(8)
                                    .background(Color(.textBackgroundColor).opacity(0.5))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Payload Helpers")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.secondary)
                                    Text("Use {text} for shell-escaped insertion, or $" + VoiceWorkflowExecutor.payloadEnvironmentKey + " inside quotes.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(#"Example: obsidian append content="$OPENSUPERWHISPER_WORKFLOW_TEXT" --active"#)
                                        .font(.caption.monospaced())
                                        .foregroundColor(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }

                    if !validationErrors.isEmpty {
                        WorkflowSettingsCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Fix Before Saving")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                                ForEach(validationErrors, id: \.self) { error in
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.orange)
                                        Text(error.localizedDescription)
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            HStack {
                Button("Cancel") {
                    onCancel()
                    dismiss()
                }
                .workflowActionButtonStyle()

                Spacer()

                Button("Save") {
                    onSave(workflowForValidation)
                    dismiss()
                }
                .workflowActionButtonStyle(prominent: true)
                .disabled(!validationErrors.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560, height: 680)
        .background(Color(.windowBackgroundColor))
    }

    private func chooseExecutable() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true

        if panel.runModal() == .OK, let url = panel.url {
            draft.executablePath = url.path
        }
    }
}

private extension View {
    @ViewBuilder
    func workflowActionButtonStyle(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                buttonStyle(.glassProminent)
            } else {
                buttonStyle(.glass)
            }
        } else {
            if prominent {
                buttonStyle(.borderedProminent)
            } else {
                buttonStyle(.bordered)
            }
        }
    }
}
