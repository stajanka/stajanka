import XCTest

@testable import Stajanka

final class ParkingTests: XCTestCase {
  func quote(extension ext: Bool = false) -> ParkingQuote {
    ParkingQuote(
      plate: "1234AA7", zoneID: "710", zoneTitle: "Тестовая зона",
      start: "2026-09-22T10:00:00.000+03:00", validTill: "2026-09-22T11:00:00.000+03:00", hours: 1,
      isExtension: ext, tariff: 1, amount: "2.0", eripURL: nil, createdAt: Date())
  }
  func response(found: Bool, till: String) -> StartResponse {
    StartResponse(
      status: "ok", details: nil, t_start: till, found: found, paid_dur: 60, hours_due: 1,
      zone_type: 0, tariff_modifier_id: 1, erip_tree_path: nil)
  }
  func testTimezoneSignEncodedForRails() {
    let url = quote().cardURL.absoluteString
    XCTAssertTrue(url.contains("%2B03:00"))
    XCTAssertFalse(url.contains("+03"))
    let components = URLComponents(string: url)!
    XCTAssertEqual(components.queryItems?.first { $0.name == "t_start" }?.value, quote().start)
  }
  func testExistingPaymentCannotConfirmExtension() {
    let checkedAt = ParkingDate.parse("2026-09-22T10:01:00+03:00")!
    XCTAssertFalse(
      quote(extension: true).isCovered(
        by: response(found: true, till: "2026-09-22T10:00:00+03:00"), checkedAt: checkedAt)
    )
    XCTAssertFalse(
      quote().isCovered(
        by: response(found: false, till: "2026-09-22T11:00:00+03:00"), checkedAt: checkedAt))
    XCTAssertTrue(
      quote().isCovered(
        by: response(found: true, till: "2026-09-22T11:00:00+03:00"), checkedAt: checkedAt))
    XCTAssertFalse(
      quote().isCovered(
        by: response(found: true, till: "2026-09-22T10:59:00+03:00"), checkedAt: checkedAt))
  }

  func testNewParkingCannotConfirmExpiredAttempt() {
    XCTAssertFalse(
      quote().isCovered(
        by: response(found: true, till: "2026-09-23T11:00:00+03:00"),
        checkedAt: ParkingDate.parse("2026-09-23T10:01:00+03:00")!))
  }

  func historyRow(_ changes: [String: Any] = [:]) throws -> HistoryRow {
    var object: [String: Any] = [
      "id": 1, "regplate_full": "1234 AA-7", "name": "Тестовая зона",
      "starts_at": "2026-09-22T10:00:00+03:00",
      "valid_till": "2026-09-22T11:00:00+03:00",
      "amount": "2.00", "parent_zone_id": 710,
    ]
    object.merge(changes) { _, new in new }
    return try JSONDecoder().decode(
      HistoryRow.self, from: JSONSerialization.data(withJSONObject: object))
  }

  func testAccountHistoryNeedsMatchingPlateZonePeriodAndAmount() throws {
    XCTAssertTrue(try historyRow().matches(quote()))
    XCTAssertTrue(try historyRow(["amount": 2]).matches(quote()))
    XCTAssertFalse(try historyRow(["regplate_full": "9999AA7"]).matches(quote()))
    XCTAssertFalse(try historyRow(["parent_zone_id": 720]).matches(quote()))
    XCTAssertFalse(try historyRow(["amount": "4.0"]).matches(quote()))
    XCTAssertFalse(try historyRow(["starts_at": "2026-09-21T10:00:00+03:00"]).matches(quote()))
    XCTAssertFalse(try historyRow(["valid_till": "2026-09-22T12:00:00+03:00"]).matches(quote()))
    XCTAssertFalse(try historyRow(["starts_at": "unrecognized date"]).matches(quote()))
    XCTAssertFalse(
      try historyRow(["parent_zone_id": NSNull(), "name": "Все зоны"]).matches(quote()))
  }

  func testOldStoredSessionRemainsReadable() throws {
    let session = ParkingSession(quote: quote(), state: .awaiting)
    let decoded = try JSONDecoder().decode(ParkingSession.self, from: JSONEncoder().encode(session))
    XCTAssertEqual(decoded.quote, session.quote)
    XCTAssertNil(decoded.confirmationSource)
    XCTAssertNil(decoded.historyRowID)
  }

  func testERIPTimerUsesActualPaidExpiry() {
    var session = ParkingSession(quote: quote(), state: .confirmed)
    session.confirmedValidTill = "2026-09-22T08:01:47.000Z"
    XCTAssertEqual(session.endDate, ParkingDate.parse("2026-09-22T11:01:47+03:00"))
    XCTAssertNotEqual(session.endDate, session.quote.endDate)
  }

  func testRestoreExternalPaymentWithoutInventingItsCost() throws {
    let data = try Data(contentsOf: Bundle.main.url(forResource: "zones", withExtension: "json")!)
    let zone = try XCTUnwrap(ParkingZone.decode(data).first { $0.paymentID == "710" })
    let vehicle = Vehicle(plate: "1234AA7", nickname: "")
    let now = ParkingDate.parse("2026-09-22T10:01:00+03:00")!
    let paid = response(found: true, till: "2026-09-22T11:00:00+03:00")
    let session = try XCTUnwrap(
      ParkingSession.restored(vehicle: vehicle, zone: zone, response: paid, now: now))
    XCTAssertEqual(session.endDate, ParkingDate.parse("2026-09-22T11:00:00+03:00"))
    XCTAssertEqual(session.quote.zoneID, "710")
    XCTAssertEqual(session.quote.amountLabel, L("Оплачено ранее"))
    XCTAssertEqual(session.state, .confirmed)
    XCTAssertNil(
      ParkingSession.restored(
        vehicle: vehicle, zone: zone,
        response: response(found: false, till: "2026-09-22T11:00:00+03:00"), now: now))
    XCTAssertNil(
      ParkingSession.restored(
        vehicle: vehicle, zone: zone, response: paid,
        now: ParkingDate.parse("2026-09-23T10:00:00+03:00")!))
  }

  func testOversizedNicknameCannotBreakGarageLayout() {
    let vehicle = Vehicle(plate: "1234AA7", nickname: String(repeating: "А", count: 10_000))
    XCTAssertEqual(vehicle.label.count, 40)
    XCTAssertEqual(Vehicle.cleanNickname("  Моя\nмашина  "), "Моя машина")
    XCTAssertEqual(Vehicle(plate: "1234AA7", nickname: " \n ").label, L("Мой автомобиль"))
  }

  func testVehicleNormalization() {
    XCTAssertEqual(Vehicle.normalize(" 1234 АА-7 "), "1234AA7")
    XCTAssertTrue(Vehicle.isValid("E123AA7"))
    XCTAssertFalse(Vehicle.isValid("<script>"))
  }
  func testMapFixturePreservesParentPaymentZones() throws {
    let url = Bundle.main.url(forResource: "zones", withExtension: "json")!
    let zones = try ParkingZone.decode(Data(contentsOf: url))
    XCTAssertGreaterThan(zones.count, 80)
    XCTAssertEqual(zones.first { $0.id == "737" }?.paymentID, "720")
    for zone in zones {
      XCTAssertFalse(zone.polygons.isEmpty)
      XCTAssertTrue((53...55).contains(zone.coordinate.latitude))
      XCTAssertTrue((26...29).contains(zone.coordinate.longitude))
    }
  }
}
