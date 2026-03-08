import Foundation
import GRDB

enum RecordingStatus: String, Codable {
    case pending
    case converting
    case transcribing
    case completed
    case failed
}

enum RecordingDeliveryKind: String, Codable {
    case transcription
    case workflow
}

enum WorkflowExecutionStatus: String, Codable {
    case running
    case succeeded
    case failed
}

struct Recording: Identifiable, Codable, FetchableRecord, PersistableRecord, Equatable {
    let id: UUID
    let timestamp: Date
    let fileName: String
    var transcription: String
    let duration: TimeInterval
    var status: RecordingStatus
    var progress: Float
    var sourceFileURL: String?
    var deliveryKind: RecordingDeliveryKind = .transcription
    var workflowName: String?
    var workflowExecutionStatus: WorkflowExecutionStatus?
    var workflowExecutionMessage: String?
    
    var isRegeneration: Bool = false
    
    enum CodingKeys: String, CodingKey {
        case id, timestamp, fileName, transcription, duration, status, progress, sourceFileURL
        case deliveryKind, workflowName, workflowExecutionStatus, workflowExecutionMessage
    }

    static func == (lhs: Recording, rhs: Recording) -> Bool {
        return lhs.id == rhs.id &&
               lhs.status == rhs.status &&
               lhs.progress == rhs.progress &&
               lhs.transcription == rhs.transcription &&
               lhs.deliveryKind == rhs.deliveryKind &&
               lhs.workflowName == rhs.workflowName &&
               lhs.workflowExecutionStatus == rhs.workflowExecutionStatus &&
               lhs.workflowExecutionMessage == rhs.workflowExecutionMessage &&
               lhs.isRegeneration == rhs.isRegeneration
    }

    static var recordingsDirectory: URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let appDirectory = applicationSupport.appendingPathComponent(Bundle.main.bundleIdentifier!)
        return appDirectory.appendingPathComponent("recordings")
    }

    var url: URL {
        Self.recordingsDirectory.appendingPathComponent(fileName)
    }
    
    var isPending: Bool {
        status == .pending || status == .converting || status == .transcribing
    }
    
    var sourceFileName: String? {
        guard let sourceFileURL = sourceFileURL else { return nil }
        return URL(fileURLWithPath: sourceFileURL).lastPathComponent
    }

    static let databaseTableName = "recordings"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let timestamp = Column(CodingKeys.timestamp)
        static let fileName = Column(CodingKeys.fileName)
        static let transcription = Column(CodingKeys.transcription)
        static let duration = Column(CodingKeys.duration)
        static let status = Column(CodingKeys.status)
        static let progress = Column(CodingKeys.progress)
        static let sourceFileURL = Column(CodingKeys.sourceFileURL)
        static let deliveryKind = Column(CodingKeys.deliveryKind)
        static let workflowName = Column(CodingKeys.workflowName)
        static let workflowExecutionStatus = Column(CodingKeys.workflowExecutionStatus)
        static let workflowExecutionMessage = Column(CodingKeys.workflowExecutionMessage)
    }
}

@MainActor
class RecordingStore: ObservableObject {
    static let shared = RecordingStore()

    @Published private(set) var recordings: [Recording] = []
    private let dbQueue: DatabaseQueue

    private init() {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let appDirectory = applicationSupport.appendingPathComponent(Bundle.main.bundleIdentifier!)
        let dbPath = appDirectory.appendingPathComponent("recordings.sqlite")

        print("Database path: \(dbPath.path)")

        do {
            try FileManager.default.createDirectory(
                at: appDirectory, withIntermediateDirectories: true)
            dbQueue = try DatabaseQueue(path: dbPath.path)
            try setupDatabase()
        } catch {
            fatalError("Failed to setup database: \(error)")
        }
    }

    nonisolated static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: Recording.databaseTableName, ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("timestamp", .datetime).notNull().indexed()
                t.column("fileName", .text).notNull()
                t.column("transcription", .text).notNull().indexed().collate(.nocase)
                t.column("duration", .double).notNull()
            }
        }
        
        migrator.registerMigration("v2_add_status") { db in
            let columns = try db.columns(in: Recording.databaseTableName)
            let columnNames = columns.map { $0.name }
            
            if !columnNames.contains("status") {
                try db.alter(table: Recording.databaseTableName) { t in
                    t.add(column: "status", .text).notNull().defaults(to: "completed")
                }
            }
            if !columnNames.contains("progress") {
                try db.alter(table: Recording.databaseTableName) { t in
                    t.add(column: "progress", .double).notNull().defaults(to: 1.0)
                }
            }
            if !columnNames.contains("sourceFileURL") {
                try db.alter(table: Recording.databaseTableName) { t in
                    t.add(column: "sourceFileURL", .text)
                }
            }
        }

        migrator.registerMigration("v3_workflow_metadata") { db in
            let columns = try db.columns(in: Recording.databaseTableName)
            let columnNames = columns.map(\.name)

            if !columnNames.contains("deliveryKind") {
                try db.alter(table: Recording.databaseTableName) { t in
                    t.add(column: "deliveryKind", .text).notNull().defaults(to: RecordingDeliveryKind.transcription.rawValue)
                }
            }
            if !columnNames.contains("workflowName") {
                try db.alter(table: Recording.databaseTableName) { t in
                    t.add(column: "workflowName", .text)
                }
            }
            if !columnNames.contains("workflowExecutionStatus") {
                try db.alter(table: Recording.databaseTableName) { t in
                    t.add(column: "workflowExecutionStatus", .text)
                }
            }
            if !columnNames.contains("workflowExecutionMessage") {
                try db.alter(table: Recording.databaseTableName) { t in
                    t.add(column: "workflowExecutionMessage", .text)
                }
            }
        }

        return migrator
    }

    private nonisolated func setupDatabase() throws {
        try Self.makeMigrator().migrate(dbQueue)
    }
    
    private nonisolated func fetchAllRecordings() async throws -> [Recording] {
        try await dbQueue.read { db in
            try Recording
                .order(Recording.Columns.timestamp.desc)
                .fetchAll(db)
        }
    }
    
    nonisolated func fetchRecordings(limit: Int, offset: Int) async throws -> [Recording] {
        try await dbQueue.read { db in
            try Recording
                .order(Recording.Columns.timestamp.desc)
                .limit(limit, offset: offset)
                .fetchAll(db)
        }
    }

    func getPendingRecordings() -> [Recording] {
        do {
            return try dbQueue.read { db in
                try Recording
                    .filter([RecordingStatus.pending.rawValue, RecordingStatus.converting.rawValue, RecordingStatus.transcribing.rawValue].contains(Recording.Columns.status))
                    .order(Recording.Columns.timestamp.asc)
                    .fetchAll(db)
            }
        } catch {
            print("Failed to get pending recordings: \(error)")
            return []
        }
    }

    func getNextPendingRecording() -> Recording? {
        do {
            return try dbQueue.read { db in
                try Recording
                    .filter([RecordingStatus.pending.rawValue, RecordingStatus.converting.rawValue, RecordingStatus.transcribing.rawValue].contains(Recording.Columns.status))
                    .order(Recording.Columns.timestamp.asc)
                    .limit(1)
                    .fetchOne(db)
            }
        } catch {
            print("Failed to get next pending recording: \(error)")
            return nil
        }
    }

    static let recordingsDidUpdateNotification = Notification.Name("RecordingStore.recordingsDidUpdate")

    func addRecording(_ recording: Recording) {
        Task {
            do {
                try await insertRecording(recording)
                await MainActor.run {
                    NotificationCenter.default.post(name: Self.recordingsDidUpdateNotification, object: nil)
                }
            } catch {
                print("Failed to add recording: \(error)")
            }
        }
    }
    
    func addRecordingSync(_ recording: Recording) async throws {
        try await insertRecording(recording)
        await MainActor.run {
            NotificationCenter.default.post(name: Self.recordingsDidUpdateNotification, object: nil)
        }
    }
    
    private nonisolated func insertRecording(_ recording: Recording) async throws {
        try await dbQueue.write { db in
            try recording.insert(db)
        }
    }
    
    func updateRecording(_ recording: Recording) {
        Task {
            do {
                try await updateRecordingInDB(recording)
                await MainActor.run {
                    NotificationCenter.default.post(name: Self.recordingsDidUpdateNotification, object: nil)
                }
            } catch {
                print("Failed to update recording: \(error)")
            }
        }
    }
    
    func updateRecordingSync(_ recording: Recording) async throws {
        try await updateRecordingInDB(recording)
        await MainActor.run {
            NotificationCenter.default.post(name: Self.recordingsDidUpdateNotification, object: nil)
        }
    }
    
    func updateRecordingProgressOnly(_ id: UUID, transcription: String, progress: Float, status: RecordingStatus) {
        Task {
            await updateRecordingProgressOnlySync(id, transcription: transcription, progress: progress, status: status)
        }
    }
    
    static let recordingProgressDidUpdateNotification = Notification.Name("RecordingStore.recordingProgressDidUpdate")
    
    func updateRecordingProgressOnlySync(_ id: UUID, transcription: String, progress: Float, status: RecordingStatus, isRegeneration: Bool? = nil) async {
        do {
            _ = try await dbQueue.write { db -> Int in
                try Recording
                    .filter(Recording.Columns.id == id)
                    .updateAll(db, [
                        Recording.Columns.transcription.set(to: transcription),
                        Recording.Columns.progress.set(to: progress),
                        Recording.Columns.status.set(to: status.rawValue)
                    ])
            }
            if let index = recordings.firstIndex(where: { $0.id == id }) {
                var updated = recordings[index]
                updated.transcription = transcription
                updated.progress = progress
                updated.status = status
                if let isRegeneration = isRegeneration {
                    updated.isRegeneration = isRegeneration
                }
                recordings[index] = updated
            }
            
            var userInfo: [String: Any] = [
                "id": id,
                "transcription": transcription,
                "progress": progress,
                "status": status
            ]
            if let isRegeneration = isRegeneration {
                userInfo["isRegeneration"] = isRegeneration
            }
            
            await MainActor.run {
                NotificationCenter.default.post(name: Self.recordingProgressDidUpdateNotification, object: nil, userInfo: userInfo)
            }
        } catch {
            print("Failed to update recording progress: \(error)")
        }
    }

    nonisolated func updateSourceFileURL(_ id: UUID, sourceURL: String) async throws {
        try await dbQueue.write { db in
            try Recording
                .filter(Recording.Columns.id == id)
                .updateAll(db, [
                    Recording.Columns.sourceFileURL.set(to: sourceURL)
                ])
        }
    }

    func updateRecordingStatusOnly(_ id: UUID, progress: Float, status: RecordingStatus, isRegeneration: Bool? = nil) async {
        do {
            _ = try await dbQueue.write { db -> Int in
                try Recording
                    .filter(Recording.Columns.id == id)
                    .updateAll(db, [
                        Recording.Columns.progress.set(to: progress),
                        Recording.Columns.status.set(to: status.rawValue)
                    ])
            }
            if let index = recordings.firstIndex(where: { $0.id == id }) {
                var updated = recordings[index]
                updated.progress = progress
                updated.status = status
                if let isRegeneration = isRegeneration {
                    updated.isRegeneration = isRegeneration
                }
                recordings[index] = updated
            }
            
            var userInfo: [String: Any] = [
                "id": id,
                "progress": progress,
                "status": status
            ]
            if let isRegeneration = isRegeneration {
                userInfo["isRegeneration"] = isRegeneration
            }
            
            await MainActor.run {
                NotificationCenter.default.post(name: Self.recordingProgressDidUpdateNotification, object: nil, userInfo: userInfo)
            }
        } catch {
            print("Failed to update recording status: \(error)")
        }
    }

    func updateWorkflowExecutionSync(_ id: UUID, status: WorkflowExecutionStatus, message: String?) async {
        do {
            _ = try await dbQueue.write { db -> Int in
                try Recording
                    .filter(Recording.Columns.id == id)
                    .updateAll(db, [
                        Recording.Columns.workflowExecutionStatus.set(to: status.rawValue),
                        Recording.Columns.workflowExecutionMessage.set(to: message)
                    ])
            }

            if let index = recordings.firstIndex(where: { $0.id == id }) {
                var updated = recordings[index]
                updated.workflowExecutionStatus = status
                updated.workflowExecutionMessage = message
                recordings[index] = updated
            }

            await MainActor.run {
                NotificationCenter.default.post(name: Self.recordingsDidUpdateNotification, object: nil)
            }
        } catch {
            print("Failed to update workflow execution: \(error)")
        }
    }

    private nonisolated func updateRecordingInDB(_ recording: Recording) async throws {
        try await dbQueue.write { db in
            try recording.update(db)
        }
    }

    func deleteRecording(_ recording: Recording) {
        if recording.isPending {
            TranscriptionQueue.shared.cancelRecording(recording.id)
        }
        
        Task {
            do {
                try await deleteRecordingFromDB(recording)
                try? FileManager.default.removeItem(at: recording.url)
                await MainActor.run {
                    NotificationCenter.default.post(name: Self.recordingsDidUpdateNotification, object: nil)
                }
            } catch {
                print("Failed to delete recording: \(error)")
            }
        }
    }
    
    private nonisolated func deleteRecordingFromDB(_ recording: Recording) async throws {
        try await dbQueue.write { db in
            _ = try recording.delete(db)
        }
    }

    func deleteAllRecordings() {
        Task {
            do {
                let allRecordings = try await fetchAllRecordings()
                for recording in allRecordings {
                    try? FileManager.default.removeItem(at: recording.url)
                }
                try await deleteAllRecordingsFromDB()
                await MainActor.run {
                    NotificationCenter.default.post(name: Self.recordingsDidUpdateNotification, object: nil)
                }
            } catch {
                print("Failed to delete all recordings: \(error)")
            }
        }
    }
    
    private nonisolated func deleteAllRecordingsFromDB() async throws {
        try await dbQueue.write { db in
            _ = try Recording.deleteAll(db)
        }
    }

    func searchRecordings(query: String) -> [Recording] {
        do {
            return try dbQueue.read { db in
                try Recording
                    .filter(Recording.Columns.transcription.like("%\(query)%").collating(.nocase))
                    .order(Recording.Columns.timestamp.desc)
                    .limit(100)
                    .fetchAll(db)
            }
        } catch {
            print("Failed to search recordings: \(error)")
            return []
        }
    }
    
    nonisolated func searchRecordingsAsync(query: String, limit: Int = 100, offset: Int = 0) async -> [Recording] {
        do {
            return try await dbQueue.read { db in
                try Recording
                    .filter(Recording.Columns.transcription.like("%\(query)%").collating(.nocase))
                    .order(Recording.Columns.timestamp.desc)
                    .limit(limit, offset: offset)
                    .fetchAll(db)
            }
        } catch {
            print("Failed to search recordings: \(error)")
            return []
        }
    }
}
