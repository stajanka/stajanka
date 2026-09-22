import XCTest

@testable import Stajanka

final class ReleaseReadinessTests: XCTestCase {
  @MainActor
  func testDeleteVehiclePreservesParkingAndSelectsRemainingVehicle() throws {
    let suite = "stajanka-deletion-test-\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let model = AppModel(defaults: defaults)
    let first = Vehicle(plate: "1234AA7", nickname: "First")
    let second = Vehicle(plate: "WA12345", nickname: "Second", countryCode: "PL")
    model.vehicles = [first, second]
    model.selectedVehicleID = first.id
    let session = ParkingSession(quote: ParkingTests().quote(), state: .confirmed)
    model.sessions = [session]
    model.removeVehicle(first)
    XCTAssertEqual(model.vehicles, [second])
    XCTAssertEqual(model.selectedVehicleID, second.id)
    XCTAssertEqual(model.sessions.first?.id, session.id)
    let reloaded = AppModel(defaults: defaults)
    XCTAssertEqual(reloaded.vehicles, [second])
    XCTAssertEqual(reloaded.sessions.first?.id, session.id)
    model.removeVehicle(second)
    XCTAssertTrue(model.vehicles.isEmpty)
    XCTAssertNil(model.selectedVehicleID)
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
