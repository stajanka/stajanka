import Foundation
import SQLite3

struct ParkingSnapshot {
  var vehicles: [Vehicle] = []
  var sessions: [ParkingSession] = []
  var selectedVehicleID: UUID?
}

/// A device-local, transactional store. JSON payloads preserve older optional fields.
@MainActor
final class LocalParkingStore {
  private var database: OpaquePointer?
  private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

  init(url: URL, legacyDefaults: UserDefaults? = nil) throws {
    let directory = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try? FileManager.default.setAttributes(
      [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
      ofItemAtPath: directory.path)
    let result = sqlite3_open_v2(
      url.path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
    guard result == SQLITE_OK else {
      let error = failure(result)
      sqlite3_close(database)
      database = nil
      throw error
    }
    do {
      sqlite3_busy_timeout(database, 1500)
      try execute("PRAGMA journal_mode=WAL")
      try execute("PRAGMA synchronous=FULL")
      try execute("CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value BLOB NOT NULL)")
      for table in ["vehicles", "sessions"] {
        try execute(
          "CREATE TABLE IF NOT EXISTS \(table) (id TEXT PRIMARY KEY, position INTEGER NOT NULL, payload BLOB NOT NULL)"
        )
      }
      if try metadata("legacy_import_v1") == nil {
        // Decode everything before writing anything. A corrupt legacy value stays recoverable.
        let snapshot = ParkingSnapshot(
          vehicles: try Self.legacy([Vehicle].self, "vehicles", legacyDefaults) ?? [],
          sessions: try Self.legacy([ParkingSession].self, "sessions", legacyDefaults) ?? [],
          selectedVehicleID: legacyDefaults?.string(forKey: "selectedVehicle").flatMap(
            UUID.init(uuidString:)))
        try transaction {
          try replace(snapshot)
          try setMetadata("legacy_import_v1", Data("1".utf8))
        }
      }
      _ = try load()
      // Also finish cleanup if a previous launch stopped just after its successful commit.
      for key in ["vehicles", "sessions", "selectedVehicle"] {
        legacyDefaults?.removeObject(forKey: key)
      }
    } catch {
      sqlite3_close(database)
      database = nil
      throw error
    }
  }

  deinit { sqlite3_close(database) }

  func load() throws -> ParkingSnapshot {
    try ParkingSnapshot(
      vehicles: records(Vehicle.self, table: "vehicles"),
      sessions: records(ParkingSession.self, table: "sessions"),
      selectedVehicleID: metadata("selectedVehicle").flatMap { String(data: $0, encoding: .utf8) }
        .flatMap(UUID.init(uuidString:)))
  }

  func save(_ snapshot: ParkingSnapshot) throws {
    try transaction { try replace(snapshot) }
  }

  private func replace(_ snapshot: ParkingSnapshot) throws {
    try replace(snapshot.vehicles, table: "vehicles")
    try replace(snapshot.sessions, table: "sessions")
    try setMetadata("selectedVehicle", snapshot.selectedVehicleID.map { Data($0.uuidString.utf8) })
  }

  private func replace<T: Encodable & Identifiable>(_ values: [T], table: String) throws
  where T.ID == UUID {
    try execute("DELETE FROM \(table)")
    let statement = try prepare("INSERT INTO \(table) (id, position, payload) VALUES (?, ?, ?)")
    defer { sqlite3_finalize(statement) }
    for (position, value) in values.enumerated() {
      sqlite3_reset(statement)
      sqlite3_clear_bindings(statement)
      try check(sqlite3_bind_text(statement, 1, value.id.uuidString, -1, transient))
      try check(sqlite3_bind_int64(statement, 2, Int64(position)))
      let data = try JSONEncoder().encode(value)
      try bind(data, to: statement, at: 3)
      try check(sqlite3_step(statement), expected: SQLITE_DONE)
    }
  }

  private func records<T: Decodable>(_ type: T.Type, table: String) throws -> [T] {
    let statement = try prepare("SELECT payload FROM \(table) ORDER BY position")
    defer { sqlite3_finalize(statement) }
    var result: [T] = []
    while true {
      let step = sqlite3_step(statement)
      if step == SQLITE_DONE { return result }
      try check(step, expected: SQLITE_ROW)
      let count = Int(sqlite3_column_bytes(statement, 0))
      guard let bytes = sqlite3_column_blob(statement, 0), count > 0 else {
        throw failure(SQLITE_CORRUPT)
      }
      result.append(try JSONDecoder().decode(type, from: Data(bytes: bytes, count: count)))
    }
  }

  private func metadata(_ key: String) throws -> Data? {
    let statement = try prepare("SELECT value FROM metadata WHERE key = ?")
    defer { sqlite3_finalize(statement) }
    try check(sqlite3_bind_text(statement, 1, key, -1, transient))
    let step = sqlite3_step(statement)
    if step == SQLITE_DONE { return nil }
    try check(step, expected: SQLITE_ROW)
    guard let bytes = sqlite3_column_blob(statement, 0) else { return Data() }
    return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
  }

  private func setMetadata(_ key: String, _ data: Data?) throws {
    let statement = try prepare(
      data == nil
        ? "DELETE FROM metadata WHERE key = ?"
        : "INSERT OR REPLACE INTO metadata (key, value) VALUES (?, ?)")
    defer { sqlite3_finalize(statement) }
    try check(sqlite3_bind_text(statement, 1, key, -1, transient))
    if let data { try bind(data, to: statement, at: 2) }
    try check(sqlite3_step(statement), expected: SQLITE_DONE)
  }

  private func bind(_ data: Data, to statement: OpaquePointer?, at index: Int32) throws {
    try data.withUnsafeBytes { buffer in
      try check(
        sqlite3_bind_blob(statement, index, buffer.baseAddress, Int32(buffer.count), transient))
    }
  }

  private func transaction(_ operation: () throws -> Void) throws {
    try execute("BEGIN IMMEDIATE")
    do {
      try operation()
      try execute("COMMIT")
    } catch {
      try? execute("ROLLBACK")
      throw error
    }
  }
  private func execute(_ sql: String) throws {
    try check(sqlite3_exec(database, sql, nil, nil, nil))
  }
  private func prepare(_ sql: String) throws -> OpaquePointer? {
    var statement: OpaquePointer?
    try check(sqlite3_prepare_v2(database, sql, -1, &statement, nil))
    return statement
  }
  private func check(_ result: Int32, expected: Int32 = SQLITE_OK) throws {
    if result != expected { throw failure(result) }
  }
  private func failure(_ code: Int32) -> Error {
    NSError(
      domain: "Stajanka.LocalParkingStore", code: Int(code),
      userInfo: [
        NSLocalizedDescriptionKey: database.map { String(cString: sqlite3_errmsg($0)) }
          ?? "Local database unavailable"
      ])
  }
  private static func legacy<T: Decodable>(_ type: T.Type, _ key: String, _ defaults: UserDefaults?)
    throws -> T?
  {
    guard let defaults, defaults.object(forKey: key) != nil else { return nil }
    guard let data = defaults.data(forKey: key) else { throw CocoaError(.coderReadCorrupt) }
    return try JSONDecoder().decode(type, from: data)
  }
}
