import Foundation
import SQLite3

public struct HistoryMetric {
    public let id: String
    public let name: String
    public let unit: String
    public let value: Double
    public init(_ id: String, _ name: String, _ unit: String, _ value: Double) {
        self.id = id; self.name = name; self.unit = unit; self.value = value
    }
}
public struct HistoryBucket: Codable {
    public var timestamp: TimeInterval
    public var firstSample: TimeInterval
    public var lastSample: TimeInterval
    public var sum: Double
    public var minimum: Double
    public var maximum: Double
    public var count: Int
    public var mean: Double { self.sum / Double(max(1, self.count)) }
}
public struct HistorySeries: Codable {
    public var id: String
    public var name: String
    public var unit: String
    public var buckets: [String: [HistoryBucket]]
}
private struct HistoryKey: Hashable {
    let module: String
    let id: String
    let resolution: Int
    let timestamp: Int
}

public final class HistoryArchive {
    public static let shared = HistoryArchive()
    public static let resolutions: [(seconds: Int, retention: TimeInterval)] = [(5, 3600), (60, 2*86400), (300, 28*86400)]
    private let directory: URL
    private let queue = DispatchQueue(label: "eu.exelban.Stats.Compact.history", qos: .utility)
    private var database: OpaquePointer?
    private var pending: [HistoryKey: HistoryBucket] = [:]
    private var metadata: [String: (String, String)] = [:]
    private var lastSave: [String: TimeInterval] = [:]
    private var lastCleanup: TimeInterval = 0
    private var errorMessage: String?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(directory: URL? = nil) {
        let name = Bundle.main.bundleIdentifier == "eu.exelban.Stats" ? "Stats" : "Stats Compact"
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name).appendingPathComponent("history-v1")
    }
    deinit { if let database { sqlite3_close(database) } }
    public var storageError: String? { self.queue.sync { self.errorMessage } }
    public static func resolution(for range: TimeInterval) -> Int { range <= 3600 ? 5 : (range <= 86400 ? 60 : 300) }

    public func record(module: String, metrics: [HistoryMetric], at date: Date = Date()) {
        let timestamp = date.timeIntervalSince1970
        let metrics = metrics.filter { $0.value.isFinite }
        guard timestamp.isFinite, !metrics.isEmpty else { return }
        self.queue.async {
            guard self.open() else { return }
            for metric in metrics {
                let key = module + ":" + metric.id
                if self.metadata[key]?.0 != metric.name || self.metadata[key]?.1 != metric.unit {
                    guard let statement = self.statement("INSERT INTO metrics(module,id,name,unit) VALUES(?,?,?,?) ON CONFLICT(module,id) DO UPDATE SET name=excluded.name,unit=excluded.unit") else { continue }
                    self.bind(module, statement, 1); self.bind(metric.id, statement, 2)
                    self.bind(metric.name, statement, 3); self.bind(metric.unit, statement, 4)
                    if sqlite3_step(statement) == SQLITE_DONE { self.metadata[key] = (metric.name, metric.unit) }
                    else { self.captureError() }
                    sqlite3_finalize(statement)
                }
                for resolution in Self.resolutions {
                    let start = Int(floor(timestamp / Double(resolution.seconds))) * resolution.seconds
                    let key = HistoryKey(module: module, id: metric.id, resolution: resolution.seconds, timestamp: start)
                    if var bucket = self.pending[key] {
                        bucket.sum += metric.value; bucket.count += 1
                        bucket.minimum = min(bucket.minimum, metric.value); bucket.maximum = max(bucket.maximum, metric.value)
                        bucket.firstSample = min(bucket.firstSample, timestamp); bucket.lastSample = max(bucket.lastSample, timestamp)
                        self.pending[key] = bucket
                    } else {
                        self.pending[key] = HistoryBucket(timestamp: Double(start), firstSample: timestamp,
                            lastSample: timestamp, sum: metric.value, minimum: metric.value, maximum: metric.value, count: 1)
                    }
                }
            }
            if timestamp - (self.lastSave[module] ?? 0) >= 60 { self.save(module, timestamp: timestamp) }
        }
    }
    public func availableSeries(module: String) -> [HistorySeries] {
        self.queue.sync {
            guard self.open(), let statement = self.statement("SELECT id,name,unit FROM metrics WHERE module=? ORDER BY id") else { return [] }
            defer { sqlite3_finalize(statement) }
            self.bind(module, statement, 1)
            var result: [HistorySeries] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                result.append(HistorySeries(id: self.text(statement, 0), name: self.text(statement, 1), unit: self.text(statement, 2), buckets: [:]))
            }
            return result
        }
    }
    public func samples(module: String, series id: String, range: TimeInterval, endingAt date: Date = Date()) -> [HistoryBucket] {
        self.queue.sync {
            guard self.open() else { return [] }
            self.save(module, timestamp: date.timeIntervalSince1970)
            let resolution = Self.resolution(for: range)
            guard let statement = self.statement("SELECT ts,first,last,sum,minimum,maximum,n FROM samples WHERE module=? AND id=? AND resolution=? AND ts>=? AND ts<=? AND last>=? ORDER BY ts") else { return [] }
            defer { sqlite3_finalize(statement) }
            let end = date.timeIntervalSince1970
            self.bind(module, statement, 1); self.bind(id, statement, 2)
            sqlite3_bind_int(statement, 3, Int32(resolution))
            sqlite3_bind_double(statement, 4, end-range-Double(resolution))
            sqlite3_bind_double(statement, 5, end)
            sqlite3_bind_double(statement, 6, end-range)
            var result: [HistoryBucket] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                result.append(HistoryBucket(timestamp: sqlite3_column_double(statement, 0), firstSample: sqlite3_column_double(statement, 1),
                    lastSample: sqlite3_column_double(statement, 2), sum: sqlite3_column_double(statement, 3),
                    minimum: sqlite3_column_double(statement, 4), maximum: sqlite3_column_double(statement, 5), count: Int(sqlite3_column_int64(statement, 6))))
            }
            return result
        }
    }
    public func flush() {
        self.queue.sync {
            for module in Set(self.pending.keys.map { $0.module }) { self.save(module, timestamp: Date().timeIntervalSince1970) }
        }
    }
    private func open() -> Bool {
        if self.database != nil { return true }
        do { try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true) }
        catch { self.errorMessage = "历史记录无法保存：\(error.localizedDescription)"; return false }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(self.directory.appendingPathComponent("history.sqlite").path, &handle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            self.errorMessage = "历史数据库无法打开。"; if let handle { sqlite3_close(handle) }; return false
        }
        self.database = handle
        sqlite3_busy_timeout(handle, 2000)
        let schema = """
        PRAGMA journal_mode=WAL;
        PRAGMA synchronous=NORMAL;
        CREATE TABLE IF NOT EXISTS metrics(module TEXT NOT NULL,id TEXT NOT NULL,name TEXT NOT NULL,unit TEXT NOT NULL,PRIMARY KEY(module,id));
        CREATE TABLE IF NOT EXISTS samples(module TEXT NOT NULL,id TEXT NOT NULL,resolution INTEGER NOT NULL,ts INTEGER NOT NULL,first REAL NOT NULL,last REAL NOT NULL,sum REAL NOT NULL,minimum REAL NOT NULL,maximum REAL NOT NULL,n INTEGER NOT NULL,PRIMARY KEY(module,id,resolution,ts));
        """
        guard self.execute(schema) else { sqlite3_close(handle); self.database = nil; return false }
        return true
    }
    private func save(_ module: String, timestamp: TimeInterval) {
        let keys = self.pending.keys.filter { $0.module == module }
        guard !keys.isEmpty, self.open(), self.execute("BEGIN IMMEDIATE") else { return }
        let sql = """
        INSERT INTO samples(module,id,resolution,ts,first,last,sum,minimum,maximum,n) VALUES(?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(module,id,resolution,ts) DO UPDATE SET first=min(first,excluded.first),last=max(last,excluded.last),sum=sum+excluded.sum,minimum=min(minimum,excluded.minimum),maximum=max(maximum,excluded.maximum),n=n+excluded.n
        """
        guard let statement = self.statement(sql) else { _ = self.execute("ROLLBACK"); return }
        var success = true
        for key in keys {
            guard let bucket = self.pending[key] else { continue }
            sqlite3_reset(statement); sqlite3_clear_bindings(statement)
            self.bind(key.module, statement, 1); self.bind(key.id, statement, 2)
            sqlite3_bind_int(statement, 3, Int32(key.resolution)); sqlite3_bind_int64(statement, 4, Int64(key.timestamp))
            sqlite3_bind_double(statement, 5, bucket.firstSample); sqlite3_bind_double(statement, 6, bucket.lastSample)
            sqlite3_bind_double(statement, 7, bucket.sum); sqlite3_bind_double(statement, 8, bucket.minimum)
            sqlite3_bind_double(statement, 9, bucket.maximum); sqlite3_bind_int64(statement, 10, Int64(bucket.count))
            if sqlite3_step(statement) != SQLITE_DONE { self.captureError(); success = false; break }
        }
        sqlite3_finalize(statement)
        if success { success = self.execute("COMMIT") }
        if success {
            keys.forEach { self.pending.removeValue(forKey: $0) }
            self.lastSave[module] = timestamp
            self.errorMessage = nil
            if timestamp-self.lastCleanup >= 3600 {
                var cleaned = true
                for resolution in Self.resolutions {
                    cleaned = self.execute("DELETE FROM samples WHERE resolution=\(resolution.seconds) AND ts<\(Int(timestamp-resolution.retention))") && cleaned
                }
                if cleaned { self.lastCleanup = timestamp }
            }
        } else { _ = self.execute("ROLLBACK") }
    }
    private func captureError() {
        self.errorMessage = "历史数据库：" + (self.database.map { String(cString: sqlite3_errmsg($0)) } ?? "无法连接")
    }
    private func execute(_ sql: String) -> Bool {
        if sqlite3_exec(self.database, sql, nil, nil, nil) == SQLITE_OK { return true }
        self.captureError(); return false
    }
    private func statement(_ sql: String) -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(self.database, sql, -1, &statement, nil) == SQLITE_OK else { self.captureError(); return nil }
        return statement
    }
    private func bind(_ value: String, _ statement: OpaquePointer, _ index: Int32) {
        _ = value.withCString { sqlite3_bind_text(statement, index, $0, -1, self.transient) }
    }
    private func text(_ statement: OpaquePointer, _ index: Int32) -> String {
        sqlite3_column_text(statement, index).map { String(cString: $0) } ?? ""
    }
}
