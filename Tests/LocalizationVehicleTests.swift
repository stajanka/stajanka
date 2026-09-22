import XCTest

@testable import Stajanka

final class LocalizationVehicleTests: XCTestCase {
  func testBelarusianIsDefaultRegardlessOfSystemLanguage() {
    XCTAssertEqual(AppLanguage.resolved(nil), .belarusian)
    XCTAssertEqual(AppLanguage.resolved("unsupported"), .belarusian)
    XCTAssertEqual(AppLanguage.resolved("en"), .english)
  }
  func testAllCatalogsAreBundledAndHaveTheSameKeys() throws {
    var reference: Set<String>?
    for language in AppLanguage.allCases {
      let bundle = L10n.bundle(for: language)
      let url = try XCTUnwrap(bundle.url(forResource: "Localizable", withExtension: "strings"))
      let object = try PropertyListSerialization.propertyList(
        from: Data(contentsOf: url), format: nil)
      let strings = try XCTUnwrap(object as? [String: String])
      XCTAssertGreaterThan(strings.count, 180)
      if let reference {
        XCTAssertEqual(Set(strings.keys), reference)
      } else {
        reference = Set(strings.keys)
      }
      for (key, value) in strings {
        XCTAssertEqual(
          key.components(separatedBy: "%@").count, value.components(separatedBy: "%@").count)
      }
    }
    XCTAssertEqual(L10n.text("Выбрать время", language: .belarusian), "Выбраць час")
    XCTAssertEqual(L10n.text("Выбрать время", language: .russian), "Выбрать время")
    XCTAssertEqual(L10n.text("Выбрать время", language: .english), "Choose time")
    XCTAssertEqual(L10n.text("Банковская карта", language: .english), "Card")
  }
  func testHourPluralFormsAndCurrencyFollowLanguage() {
    XCTAssertEqual(L10n.hoursWord(1, language: .belarusian), "гадзіна")
    XCTAssertEqual(L10n.hoursWord(21, language: .belarusian), "гадзіна")
    XCTAssertEqual(L10n.hoursWord(22, language: .belarusian), "гадзіны")
    XCTAssertEqual(L10n.hoursWord(11, language: .belarusian), "гадзін")
    XCTAssertEqual(L10n.hoursWord(21, language: .russian), "час")
    XCTAssertEqual(L10n.hoursWord(21, language: .english), "hours")
    XCTAssertEqual(L10n.money("2.0", language: .english), "2.00 BYN")
    XCTAssertEqual(L10n.money("2.0", language: .belarusian), "2,00 BYN")
  }
  func testExistingVehicleMigratesWithoutLosingIDOrPlate() throws {
    let id = UUID()
    let old = ["id": id.uuidString, "plate": "1234AA7", "nickname": "My car"]
    let car = try JSONDecoder().decode(
      Vehicle.self, from: JSONSerialization.data(withJSONObject: old))
    XCTAssertEqual(car.id, id)
    XCTAssertEqual(car.plate, "1234AA7")
    XCTAssertEqual(car.countryCode, "BY")
    XCTAssertFalse(car.isBus)
  }
  func testCountryPersistsAndSelectsCorrectFlag() throws {
    let car = Vehicle(plate: "WA12345", nickname: "", countryCode: "PL")
    let restored = try JSONDecoder().decode(Vehicle.self, from: JSONEncoder().encode(car))
    XCTAssertEqual(restored.countryCode, "PL")
    XCTAssertEqual(VehicleCountry.flag(restored.countryCode), "🇵🇱")
    XCTAssertEqual(VehicleCountry.flag("BY"), "🇧🇾")
    XCTAssertEqual(VehicleCountry.flag("GB"), "🇬🇧")
    XCTAssertTrue(VehicleCountry.codes.contains("PL"))
    XCTAssertTrue(VehicleCountry.codes.contains("US"))
  }
  func testOldPaymentCountryDefaultsToUnknownAndKeepsValidQuote() throws {
    let quote = ParkingTests().quote()
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(quote)) as? [String: Any])
    object.removeValue(forKey: "countryCode")
    let decoded = try JSONDecoder().decode(
      ParkingQuote.self, from: JSONSerialization.data(withJSONObject: object))
    XCTAssertNil(decoded.countryCode)
    XCTAssertEqual(decoded.plate, quote.plate)
    XCTAssertEqual(decoded.cardURL, quote.cardURL)
  }
}
