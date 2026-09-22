import XCTest

final class AppStoreScreenshots: XCTestCase {
  func testCaptureStoreScreens() throws {
    guard ProcessInfo.processInfo.environment["STAJANKA_CAPTURE_SCREENSHOTS"] == "1" else {
      throw XCTSkip("Run only in the isolated App Store screenshot simulator")
    }
    for language in ["be", "ru", "en"] {
      let app = XCUIApplication()
      app.launchArguments = [
        "--ui-testing", "--reset-test-state", "--app-store-screenshots", "--screenshot-language",
        language,
      ]
      app.launch()
      XCTAssertTrue(app.buttons["map-welcome"].waitForExistence(timeout: 10))
      // Let MapKit finish the initial tile render; no private location or account is used.
      sleep(3)
      capture(app, "\(language)-01-map")
      app.buttons["search-zones"].tap()
      let search = app.searchFields.firstMatch
      XCTAssertTrue(search.waitForExistence(timeout: 5))
      search.tap()
      search.typeText("Кирова")
      let zone = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Кирова"))
        .firstMatch
      XCTAssertTrue(zone.waitForExistence(timeout: 5))
      zone.tap()
      XCTAssertTrue(app.buttons["zone-continue"].waitForExistence(timeout: 5))
      capture(app, "\(language)-02-zone")
      app.buttons["zone-continue"].tap()
      XCTAssertTrue(app.buttons["pay-parking"].waitForExistence(timeout: 5))
      capture(app, "\(language)-03-payment")
      app.buttons["payment-vehicle"].tap()
      XCTAssertTrue(app.buttons["choose-vehicle-WA12345"].waitForExistence(timeout: 5))
      capture(app, "\(language)-04-vehicles")
      app.buttons["choose-vehicle-1234AA7"].tap()
      app.buttons["sheet-close"].tap()
      app.buttons["tab-1"].tap()
      capture(app, "\(language)-05-timer")
      app.buttons["tab-2"].tap()
      capture(app, "\(language)-06-garage")
      app.terminate()
    }
  }
  private func capture(_ app: XCUIApplication, _ name: String) {
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = name
    screenshot.lifetime = .keepAlways
    add(screenshot)
  }
}
