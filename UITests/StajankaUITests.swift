import XCTest

final class StajankaUITests: XCTestCase {
  private func launchClean() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["--ui-testing", "--reset-test-state"]
    app.launch()
    if app.buttons["skip-onboarding"].waitForExistence(timeout: 5) {
      app.buttons["skip-onboarding"].tap()
    }
    return app
  }
  private func waitForQuote(_ app: XCUIApplication) {
    let pay = app.buttons["pay-parking"]
    XCTAssertTrue(pay.waitForExistence(timeout: 10))
    expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: pay)
    waitForExpectations(timeout: 30)
  }
  private func saveCar(_ app: XCUIApplication, plate: String, country: String? = nil) {
    if let country {
      app.buttons["vehicle-country"].tap()
      let choice = app.buttons["country-\(country)"]
      XCTAssertTrue(choice.waitForExistence(timeout: 5))
      choice.tap()
    }
    let field = app.textFields["vehicle-plate"]
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.tap()
    field.typeText(plate)
    app.swipeUp()
    app.buttons["save-vehicle"].tap()
  }
  func testFirstRunGarageAndLiveQuote() {
    let app = launchClean()
    XCTAssertEqual(app.buttons["tab-0"].label, "Карта")
    let welcome = app.buttons["map-welcome"]
    XCTAssertTrue(welcome.waitForExistence(timeout: 5))
    XCTAssertLessThan(welcome.frame.height, 120)
    for id in ["map-zoom-in", "map-zoom-out"] {
      let button = app.buttons[id]
      XCTAssertTrue(button.isHittable)
      XCTAssertGreaterThanOrEqual(button.frame.height, 44)
      button.tap()
    }
    app.buttons["tab-2"].tap()
    app.buttons["add-vehicle"].tap()
    saveCar(app, plate: "1234AA7")
    XCTAssertTrue(app.staticTexts["1234AA7"].waitForExistence(timeout: 5))
    app.buttons["tab-0"].tap()
    app.buttons["search-zones"].tap()
    let search = app.searchFields.firstMatch
    XCTAssertTrue(search.waitForExistence(timeout: 4))
    search.tap()
    search.typeText("Кирова")
    let zone = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Кирова"))
      .firstMatch
    XCTAssertTrue(zone.waitForExistence(timeout: 8))
    zone.tap()
    app.buttons["zone-continue"].tap()
    waitForQuote(app)
    app.buttons["duration-2"].tap()
    waitForQuote(app)
    app.buttons["payment-vehicle"].tap()
    app.buttons["payment-add-vehicle"].tap()
    saveCar(app, plate: "WA12345", country: "PL")
    let selected = app.buttons["payment-vehicle"]
    expectation(for: NSPredicate(format: "value CONTAINS %@", "WA12345"), evaluatedWith: selected)
    waitForExpectations(timeout: 10)
    waitForQuote(app)
    XCTAssertTrue((selected.value as? String ?? "").contains("PL"))
    selected.tap()
    app.buttons["choose-vehicle-1234AA7"].tap()
    waitForQuote(app)
    XCTAssertTrue((selected.value as? String ?? "").contains("1234AA7"))
    XCTAssertTrue((selected.value as? String ?? "").contains("BY"))
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "Belarusian payment and vehicle switch"
    attachment.lifetime = .keepAlways
    add(attachment)
    // Never tap Pay: these tests only calculate quotes and create local vehicles.
  }
  func testThreeLanguagesSwitchAndPersist() {
    let app = launchClean()
    app.buttons["tab-2"].tap()
    XCTAssertTrue(app.staticTexts["Мой гараж"].exists)
    app.buttons["language-settings"].tap()
    app.buttons["language-en"].tap()
    XCTAssertTrue(app.staticTexts["My garage"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.buttons["tab-0"].label, "Map")
    app.terminate()
    app.launchArguments = ["--ui-testing"]
    app.launch()
    XCTAssertTrue(app.buttons["tab-0"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.buttons["tab-0"].label, "Map")
    app.buttons["tab-2"].tap()
    app.buttons["language-settings"].tap()
    app.buttons["language-ru"].tap()
    XCTAssertTrue(app.staticTexts["Мой гараж"].waitForExistence(timeout: 5))
    XCTAssertEqual(app.buttons["tab-1"].label, "Парковка")
    app.buttons["language-settings"].tap()
    app.buttons["language-be"].tap()
    XCTAssertEqual(app.buttons["tab-1"].label, "Паркоўка")
  }
}
