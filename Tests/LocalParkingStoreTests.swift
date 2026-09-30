import XCTest

@testable import Stajanka

final class LocalParkingStoreTests: XCTestCase {
  @MainActor
  func testLegacyMigrationPreservesCountriesConfirmationAndSelection() throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }
    let legacyCar = Vehicle(plate: "1234AA7", nickname: "Legacy")
    let foreignCar = Vehicle(plate: "WA12345", nickname: "Travel", countryCode: "PL")
    var vehicleJSON = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode([legacyCar, foreignCar]))
        as? [[String: Any]])
    vehicleJSON[0].removeValue(forKey: "countryCode")
    fixture.defaults.set(
      try JSONSerialization.data(withJSONObject: vehicleJSON), forKey: "vehicles")
    var confirmed = ParkingSession(quote: quote(), state: .confirmed)
    confirmed.confirmationSource = .accountHistory
    confirmed.historyRowID = 42
    confirmed.confirmedValidTill = "2026-09-22T08:01:47Z"
    confirmed.lastChecked = Date(timeIntervalSince1970: 1_790_000_000)
    let pending = ParkingSession(quote: quote(amount: "4.0"), state: .awaiting)
    fixture.defaults.set(try JSONEncoder().encode([pending, confirmed]), forKey: "sessions")
    fixture.defaults.set(foreignCar.id.uuidString, forKey: "selectedVehicle")
    fixture.defaults.set("en", forKey: "appLanguage")
    fixture.defaults.set(true, forKey: "onboarded")

    let store = try LocalParkingStore(url: fixture.url, legacyDefaults: fixture.defaults)
    let restored = try store.load()
    XCTAssertEqual(restored.vehicles, [legacyCar, foreignCar])
    XCTAssertEqual(restored.selectedVehicleID, foreignCar.id)
    XCTAssertEqual(restored.sessions.map(\.id), [pending.id, confirmed.id])
    XCTAssertEqual(restored.sessions[1].confirmationSource, .accountHistory)
    XCTAssertEqual(restored.sessions[1].historyRowID, 42)
    XCTAssertEqual(restored.sessions[1].confirmedValidTill, confirmed.confirmedValidTill)
    XCTAssertEqual(restored.sessions[1].lastChecked, confirmed.lastChecked)
    XCTAssertNil(fixture.defaults.object(forKey: "vehicles"))
    XCTAssertNil(fixture.defaults.object(forKey: "sessions"))
    XCTAssertNil(fixture.defaults.object(forKey: "selectedVehicle"))
    XCTAssertEqual(fixture.defaults.string(forKey: "appLanguage"), "en")
    XCTAssertTrue(fixture.defaults.bool(forKey: "onboarded"))
  }

  @MainActor
  func testMigrationRunsOnceEvenIfLegacyKeysReappear() throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }
    let original = ParkingSession(quote: quote(), state: .confirmed)
    fixture.defaults.set(try JSONEncoder().encode([original]), forKey: "sessions")
    let store = try LocalParkingStore(url: fixture.url, legacyDefaults: fixture.defaults)
    XCTAssertEqual(try store.load().sessions.map(\.id), [original.id])
    let local = ParkingSession(quote: quote(amount: ""), state: .confirmed)
    try store.save(ParkingSnapshot(vehicles: [], sessions: [local], selectedVehicleID: nil))
    fixture.defaults.set(try JSONEncoder().encode([original]), forKey: "sessions")

    let reopened = try LocalParkingStore(url: fixture.url, legacyDefaults: fixture.defaults)
    XCTAssertEqual(try reopened.load().sessions.map(\.id), [local.id])
    XCTAssertEqual(try reopened.load().sessions.first?.quote.amount, "")
  }

  @MainActor
  func testMalformedLegacyHistoryIsRetainedAndCanBeRetried() throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }
    let vehicle = Vehicle(plate: "1234AA7", nickname: "Recovery")
    let cars = try JSONEncoder().encode([vehicle])
    let damaged = Data("{not valid parking history".utf8)
    fixture.defaults.set(cars, forKey: "vehicles")
    fixture.defaults.set(damaged, forKey: "sessions")
    fixture.defaults.set(vehicle.id.uuidString, forKey: "selectedVehicle")

    XCTAssertThrowsError(try LocalParkingStore(url: fixture.url, legacyDefaults: fixture.defaults))
    XCTAssertEqual(fixture.defaults.data(forKey: "vehicles"), cars)
    XCTAssertEqual(fixture.defaults.data(forKey: "sessions"), damaged)
    XCTAssertEqual(fixture.defaults.string(forKey: "selectedVehicle"), vehicle.id.uuidString)

    let recovered = ParkingSession(quote: quote(), state: .confirmed)
    fixture.defaults.set(try JSONEncoder().encode([recovered]), forKey: "sessions")
    let retry = try LocalParkingStore(url: fixture.url, legacyDefaults: fixture.defaults)
    let restored = try retry.load()
    XCTAssertEqual(restored.vehicles, [vehicle])
    XCTAssertEqual(restored.sessions.map(\.id), [recovered.id])
    XCTAssertEqual(restored.selectedVehicleID, vehicle.id)
    XCTAssertNil(fixture.defaults.data(forKey: "sessions"))
  }

  @MainActor
  func testFailedSnapshotWriteRollsBackGarageAndHistoryTogether() throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }
    let store = try LocalParkingStore(url: fixture.url)
    let vehicle = Vehicle(plate: "1234AA7", nickname: "Original")
    let original = ParkingSession(quote: quote(), state: .confirmed)
    try store.save(
      ParkingSnapshot(vehicles: [vehicle], sessions: [original], selectedVehicleID: vehicle.id))
    let duplicate = ParkingSession(quote: quote(amount: "4.0"), state: .awaiting)
    let invalid = ParkingSnapshot(
      vehicles: [], sessions: [duplicate, duplicate], selectedVehicleID: nil)

    XCTAssertThrowsError(try store.save(invalid))
    let afterFailure = try store.load()
    XCTAssertEqual(afterFailure.vehicles, [vehicle])
    XCTAssertEqual(afterFailure.sessions.map(\.id), [original.id])
    XCTAssertEqual(afterFailure.selectedVehicleID, vehicle.id)

    // A rollback must also release the transaction so a subsequent valid change can commit.
    try store.save(ParkingSnapshot(vehicles: [], sessions: [original], selectedVehicleID: nil))
    let reopened = try LocalParkingStore(url: fixture.url)
    XCTAssertTrue(try reopened.load().vehicles.isEmpty)
    XCTAssertEqual(try reopened.load().sessions.map(\.id), [original.id])
    XCTAssertNil(try reopened.load().selectedVehicleID)
  }

  @MainActor
  func testUnknownPriceAndExpiredHistorySurviveRelaunchWithoutVehicle() throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }
    let store = try LocalParkingStore(url: fixture.url)
    var session = ParkingSession(quote: quote(amount: "", country: "PL"), state: .confirmed)
    session.confirmationSource = .currentCoverage
    session.confirmedValidTill = "2026-09-22T08:01:47Z"
    try store.save(ParkingSnapshot(vehicles: [], sessions: [session], selectedVehicleID: nil))

    let reopened = try LocalParkingStore(url: fixture.url)
    let restored = try XCTUnwrap(reopened.load().sessions.first)
    XCTAssertEqual(restored.id, session.id)
    XCTAssertEqual(restored.state, .confirmed)
    XCTAssertEqual(restored.quote.countryCode, "PL")
    XCTAssertEqual(restored.quote.amount, "", "An unknown paid amount must not become zero")
    XCTAssertEqual(restored.quote, session.quote)
    XCTAssertEqual(restored.endDate, session.endDate)
  }

  private func quote(amount: String = "2.0", country: String? = "BY") -> ParkingQuote {
    ParkingQuote(
      plate: "1234AA7", zoneID: "710", zoneTitle: "Test parking",
      start: "2026-09-22T10:00:00+03:00", validTill: "2026-09-22T11:00:00+03:00",
      hours: 1, isExtension: false, tariff: 1, amount: amount, eripURL: nil,
      createdAt: Date(timeIntervalSince1970: 1_790_000_000), countryCode: country)
  }

  private struct Fixture {
    let directory: URL
    let url: URL
    let suite: String
    let defaults: UserDefaults
    init() throws {
      let id = UUID().uuidString
      directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "stajanka-store-test-\(id)", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      url = directory.appendingPathComponent("parking.sqlite")
      suite = "by.stajanka.store-test.\(id)"
      defaults = UserDefaults(suiteName: suite)!
    }
    func cleanUp() {
      defaults.removePersistentDomain(forName: suite)
      try? FileManager.default.removeItem(at: directory)
    }
  }
}
