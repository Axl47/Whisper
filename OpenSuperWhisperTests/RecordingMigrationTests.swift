import XCTest
import GRDB
@testable import OpenSuperWhisper

final class RecordingMigrationTests: XCTestCase {
    func testMigrator_addsWorkflowColumnsWithDefaults() throws {
        let dbQueue = try DatabaseQueue()

        var legacyMigrator = DatabaseMigrator()
        legacyMigrator.registerMigration("v1") { db in
            try db.create(table: Recording.databaseTableName) { t in
                t.column("id", .text).primaryKey()
                t.column("timestamp", .datetime).notNull()
                t.column("fileName", .text).notNull()
                t.column("transcription", .text).notNull()
                t.column("duration", .double).notNull()
            }
        }
        legacyMigrator.registerMigration("v2_add_status") { db in
            try db.alter(table: Recording.databaseTableName) { t in
                t.add(column: "status", .text).notNull().defaults(to: RecordingStatus.completed.rawValue)
                t.add(column: "progress", .double).notNull().defaults(to: 1.0)
                t.add(column: "sourceFileURL", .text)
            }
        }

        try legacyMigrator.migrate(dbQueue)

        let recordingID = UUID()
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO recordings (id, timestamp, fileName, transcription, duration, status, progress, sourceFileURL)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    recordingID.uuidString,
                    Date(),
                    "sample.wav",
                    "hello world",
                    2.0,
                    RecordingStatus.completed.rawValue,
                    1.0,
                    nil
                ]
            )
        }

        try RecordingStore.makeMigrator().migrate(dbQueue)

        let fetched = try dbQueue.read { db in
            try Recording.fetchOne(db, key: recordingID.uuidString)
        }

        XCTAssertEqual(fetched?.deliveryKind, .transcription)
        XCTAssertNil(fetched?.workflowName)
        XCTAssertNil(fetched?.workflowExecutionStatus)
        XCTAssertNil(fetched?.workflowExecutionMessage)
    }
}
