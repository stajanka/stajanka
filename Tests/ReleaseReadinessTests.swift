import XCTest

@testable import Stajanka

final class ReleaseReadinessTests: XCTestCase {
  @MainActor
  func testDeleteVehiclePreservesParkingAndSelectsRemainingVehicle() throws {
    let suite = "stajanka-deletion-test-\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let storageURL = directory.appendingPathComponent("parking.sqlite")
    defer {
      defaults.removePersistentDomain(forName: suite)
      try? FileManager.default.removeItem(at: directory)
    }
    let first = Vehicle(plate: "1234AA7", nickname: "First")
    let second = Vehicle(plate: "WA12345", nickname: "Second", countryCode: "PL")
    let session = ParkingSession(quote: ParkingTests().quote(), state: .confirmed)
    let store = try LocalParkingStore(url: storageURL, legacyDefaults: defaults)
    try store.save(
      ParkingSnapshot(
        vehicles: [first, second], sessions: [session], selectedVehicleID: first.id))
    let model = AppModel(defaults: defaults, storageURL: storageURL)
    model.removeVehicle(first)
    XCTAssertEqual(model.vehicles, [second])
    XCTAssertEqual(model.selectedVehicleID, second.id)
    XCTAssertEqual(model.sessions.first?.id, session.id)
    let reloaded = AppModel(defaults: defaults, storageURL: storageURL)
    XCTAssertEqual(reloaded.vehicles, [second])
    XCTAssertEqual(reloaded.sessions.first?.id, session.id)
    model.removeVehicle(second)
    XCTAssertTrue(model.vehicles.isEmpty)
    XCTAssertNil(model.selectedVehicleID)
  }

  @MainActor
  func testPaymentDoesNotBeginWhenLocalDatabaseCannotOpen() throws {
    let suite = "stajanka-storage-failure-test-\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
      defaults.removePersistentDomain(forName: suite)
      try? FileManager.default.removeItem(at: directory)
    }
    // SQLite cannot open a directory as a database, without changing real app storage.
    let model = AppModel(defaults: defaults, storageURL: directory)
    XCTAssertFalse(model.begin(ParkingTests().quote()))
    XCTAssertTrue(model.sessions.isEmpty)
  }
  func testLegalDocumentsAndPrivacyManifestAreBundled() throws {
    for language in ["be", "ru", "en"] {
      for kind in ["privacy", "terms", "support"] {
        let url = try XCTUnwrap(
          Bundle.main.url(forResource: "\(kind)-\(language)", withExtension: "json"))
        let document = try JSONDecoder().decode(LegalDocument.self, from: Data(contentsOf: url))
        XCTAssertFalse(document.sections.isEmpty)
        XCTAssertTrue(document.sections.contains { $0.body.contains("sosambus@icloud.com") })
      }
    }
    let url = try XCTUnwrap(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
    let manifest = try XCTUnwrap(
      PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        as? [String: Any])
    XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
    let apis = try XCTUnwrap(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
    XCTAssertEqual(apis.first?["NSPrivacyAccessedAPITypeReasons"] as? [String], ["CA92.1"])
  }
}
