import Foundation
import GRDB

/// One cached feature row. Every lookup result is persisted, including misses,
/// so each track is fetched at most once.
public struct CachedFeature: Equatable, Codable, FetchableRecord, PersistableRecord {
    public let id: String
    public let title: String
    public let artist: String
    public let bpm: Double?
    public let camelot: String?
    public let musicalKey: String?
    public let source: String
    public let state: LookupState
    public let fetchedAt: Int
    /// Estimator confidence (0...1) for DSP-sourced rows; nil for network/legacy rows.
    public let confidence: Double?

    public init(id: String, title: String, artist: String, bpm: Double?, camelot: String?,
                musicalKey: String?, source: String, state: LookupState, fetchedAt: Int,
                confidence: Double? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.bpm = bpm
        self.camelot = camelot
        self.musicalKey = musicalKey
        self.source = source
        self.state = state
        self.fetchedAt = fetchedAt
        self.confidence = confidence
    }

    public static let databaseTableName = "feature_cache"
    enum CodingKeys: String, CodingKey {
        case id, title, artist, bpm, camelot
        case musicalKey = "musical_key"
        case source, state
        case fetchedAt = "fetched_at"
        case confidence
    }
}

/// SQLite-backed feature cache. No TTL — BPM/key are immutable.
public final class FeatureCache {
    private let dbQueue: DatabaseQueue

    public init(path: String) throws {
        dbQueue = path == ":memory:" ? try DatabaseQueue() : try DatabaseQueue(path: path)
        try Self.migrator.migrate(dbQueue)
    }

    private static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.create(table: "feature_cache") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("artist", .text).notNull()
                t.column("bpm", .double)
                t.column("camelot", .text)
                t.column("musical_key", .text)
                t.column("source", .text).notNull()
                t.column("state", .text).notNull()
                t.column("fetched_at", .integer).notNull()
            }
        }
        m.registerMigration("v2-confidence") { db in
            try db.alter(table: "feature_cache") { t in
                t.add(column: "confidence", .double)   // nullable: legacy/network rows have none
            }
        }
        return m
    }

    public func upsert(_ f: CachedFeature) throws {
        try dbQueue.write { db in try f.save(db) }
    }

    public func fetch(id: String) throws -> CachedFeature? {
        try dbQueue.read { db in try CachedFeature.fetchOne(db, key: id) }
    }

    public struct Coverage: Equatable {
        public let rows: Int
        public let withCamelot: Int
        public let withBpm: Int
        public init(rows: Int, withCamelot: Int, withBpm: Int) {
            self.rows = rows; self.withCamelot = withCamelot; self.withBpm = withBpm
        }
    }

    /// Row counts for a scan summary: total rows, rows with a Camelot key, rows with a BPM.
    public func coverage() throws -> Coverage {
        try dbQueue.read { db in
            Coverage(
                rows: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM feature_cache") ?? 0,
                withCamelot: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM feature_cache WHERE camelot IS NOT NULL") ?? 0,
                withBpm: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM feature_cache WHERE bpm IS NOT NULL") ?? 0
            )
        }
    }
}
