import SwiftUI

@MainActor
struct MainOverlayView: View {
    @ObservedObject var viewModel: ContentViewModel
    @ObservedObject var permissionsManager: PermissionsManager
    @ObservedObject var overlayState: MainOverlayViewState

    let onClose: () -> Void
    let onOpenSettings: () -> Void
    let onOpenOnboarding: () -> Void

    @State private var debouncedSearchText = ""
    @State private var searchTask: Task<Void, Never>?

    private var quickActions: [OverlayQuickAction] {
        let hasPermissions = permissionsManager.isMicrophonePermissionGranted
            && permissionsManager.isAccessibilityPermissionGranted

        let allActions = [
            OverlayQuickAction(
                id: "record",
                symbolName: "mic.fill",
                title: "Start Recording",
                subtitle: "Begin a new microphone recording from the overlay",
                isDestructive: false,
                perform: {
                    viewModel.startRecording()
                }
            ),
            OverlayQuickAction(
                id: "stop",
                symbolName: "stop.fill",
                title: "Stop Recording",
                subtitle: "Finish the active recording and start transcription",
                isDestructive: false,
                perform: {
                    viewModel.startDecoding()
                }
            ),
            OverlayQuickAction(
                id: "settings",
                symbolName: "gearshape.fill",
                title: "Open Settings",
                subtitle: "Show the full settings window",
                isDestructive: false,
                perform: {
                    onOpenSettings()
                }
            ),
            OverlayQuickAction(
                id: "permissions",
                symbolName: "hand.raised.fill",
                title: "Open Permissions",
                subtitle: "Request or open the missing system permissions",
                isDestructive: false,
                perform: {
                    if !permissionsManager.isAccessibilityPermissionGranted {
                        permissionsManager.openSystemPreferences(for: .accessibility)
                    } else {
                        permissionsManager.requestMicrophonePermissionOrOpenSystemPreferences()
                    }
                }
            ),
            OverlayQuickAction(
                id: "clear-search",
                symbolName: "xmark.circle.fill",
                title: "Clear Search",
                subtitle: "Reset the transcript search and show recent history again",
                isDestructive: false,
                perform: {
                    overlayState.commandText = ""
                }
            ),
            OverlayQuickAction(
                id: "delete-all",
                symbolName: "trash.fill",
                title: "Delete All Recordings",
                subtitle: "Remove every saved recording from history",
                isDestructive: true,
                perform: {
                    viewModel.deleteAllRecordings()
                }
            ),
            OverlayQuickAction(
                id: "onboarding",
                symbolName: "sparkles",
                title: "Open Onboarding",
                subtitle: "Revisit the first-run setup flow",
                isDestructive: false,
                perform: {
                    onOpenOnboarding()
                }
            )
        ]

        return allActions.filter { action in
            switch action.id {
            case "record":
                return !viewModel.isRecording && hasPermissions
            case "stop":
                return viewModel.isRecording
            case "permissions":
                return !hasPermissions
            case "delete-all":
                return !viewModel.recordings.isEmpty
            default:
                return true
            }
        }
        .filter { action in
            let query = overlayState.quickActionQuery
            guard !query.isEmpty else { return true }
            return action.title.localizedCaseInsensitiveContains(query)
                || action.subtitle.localizedCaseInsensitiveContains(query)
        }
    }

    private var selectedRecordingID: UUID? {
        guard overlayState.commandMode == .search,
              overlayState.selectedIndex < viewModel.recordings.count else {
            return nil
        }
        return viewModel.recordings[overlayState.selectedIndex].id
    }

    var body: some View {
        ZStack {
            Color.clear

            OverlayGlassContainer {
                OverlayOuterSurface {
                    VStack(spacing: 18) {
                        OverlayCommandBar(
                            overlayState: overlayState,
                            onMoveSelection: moveSelection,
                            onSubmit: submitSelection,
                            onEscape: handleEscape
                        )

                        if overlayState.commandMode == .quickActions {
                            OverlayInsetSurface(tone: .content, cornerRadius: 28) {
                                OverlayQuickActionsList(
                                    actions: quickActions,
                                    selectedIndex: overlayState.selectedIndex,
                                    onSelect: { index in
                                        overlayState.selectedIndex = index
                                    },
                                    onActivate: { index in
                                        guard quickActions.indices.contains(index) else { return }
                                        quickActions[index].perform()
                                    }
                                )
                                .padding(12)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        } else {
                            VStack(spacing: 18) {
                                if arePermissionsGranted {
                                    OverlayInsetSurface(tone: .content, cornerRadius: 28) {
                                        MainRecordingsListSection(
                                            viewModel: viewModel,
                                            searchQuery: debouncedSearchText,
                                            selectedRecordingID: selectedRecordingID
                                        )
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    }

                                    OverlayInsetSurface(tone: .footer, cornerRadius: 24) {
                                        MainRecorderFooterSection(
                                            viewModel: viewModel,
                                            onOpenSettings: onOpenSettings
                                        )
                                        .padding(16)
                                    }
                                } else {
                                    OverlayInsetSurface(tone: .content, cornerRadius: 28) {
                                        PermissionsView(permissionsManager: permissionsManager)
                                            .padding(16)
                                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(18)

            if viewModel.transcriptionService.isLoading && arePermissionsGranted {
                ZStack {
                    Color.black.opacity(0.28)
                    VStack(spacing: 14) {
                        ProgressView()
                            .scaleEffect(1.4)
                        Text("Loading Whisper Model...")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 30))
                .padding(18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.24),
                    Color.clear,
                    Color.black.opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .fileDropHandler()
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
        .onChange(of: overlayState.commandText) { _, newValue in
            handleCommandTextChange(newValue)
        }
        .onChange(of: viewModel.recordings.count) { _, _ in
            overlayState.clampSelection(totalCount: selectionCount)
        }
        .onChange(of: viewModel.shouldClearSearch) { _, shouldClear in
            if shouldClear {
                overlayState.commandText = ""
                debouncedSearchText = ""
                searchTask?.cancel()
                viewModel.shouldClearSearch = false
            }
        }
        .onDisappear {
            searchTask?.cancel()
        }
    }

    private var selectionCount: Int {
        overlayState.commandMode == .quickActions ? quickActions.count : viewModel.recordings.count
    }

    private var arePermissionsGranted: Bool {
        permissionsManager.isMicrophonePermissionGranted
            && permissionsManager.isAccessibilityPermissionGranted
    }

    private func moveSelection(_ delta: Int) {
        overlayState.moveSelection(by: delta, totalCount: selectionCount)
    }

    private func submitSelection() {
        switch overlayState.commandMode {
        case .quickActions:
            guard quickActions.indices.contains(overlayState.selectedIndex) else { return }
            quickActions[overlayState.selectedIndex].perform()
        case .search:
            guard viewModel.recordings.indices.contains(overlayState.selectedIndex) else { return }
            let recording = viewModel.recordings[overlayState.selectedIndex]
            guard !recording.transcription.isEmpty else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(recording.transcription, forType: .string)
            onClose()
        }
    }

    private func handleEscape() {
        switch overlayState.commandMode {
        case .quickActions:
            overlayState.commandText = ""
        case .search:
            if !overlayState.commandText.isEmpty {
                overlayState.commandText = ""
            } else {
                onClose()
            }
        }
    }

    private func handleCommandTextChange(_ query: String) {
        overlayState.selectedIndex = 0
        searchTask?.cancel()

        if overlayState.commandMode == .quickActions {
            debouncedSearchText = ""
            viewModel.search(query: "")
            return
        }

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
}

private struct OverlayQuickActionsList: View {
    let actions: [OverlayQuickAction]
    let selectedIndex: Int
    let onSelect: (Int) -> Void
    let onActivate: (Int) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if actions.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "command")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text("No quick actions match")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("Try a different action name after `>`.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 48)
                } else {
                    ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                        Button {
                            onActivate(index)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: action.symbolName)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(action.isDestructive ? .red : .primary)
                                    .frame(width: 18)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(action.title)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(action.isDestructive ? .red : .primary)
                                    Text(action.subtitle)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(index == selectedIndex ? Color.accentColor.opacity(0.14) : Color.clear)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(
                                        index == selectedIndex
                                            ? Color.accentColor.opacity(0.32)
                                            : Color.white.opacity(0.08),
                                        lineWidth: 1
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            if hovering {
                                onSelect(index)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 6)
        }
        .scrollIndicators(.hidden)
    }
}
