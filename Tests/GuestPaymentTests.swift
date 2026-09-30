import XCTest
import Security

@testable import Stajanka

final class GuestPaymentTests: XCTestCase {
  func testRetiredAccountCredentialIsRemovedWithoutRestoringIt() async throws {
    let service = "by.stajanka.legacy-fixture.\(UUID())"
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: "cookies",
    ]
    defer { SecItemDelete(query as CFDictionary) }
    var addition = query
    addition[kSecValueData as String] = Data("fixture-only-retired-session".utf8)
    XCTAssertEqual(SecItemAdd(addition as CFDictionary, nil), errSecSuccess)
    let api = ParkoukaAPI(configuration: .ephemeral, legacyCookieService: service)
    XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, nil), errSecItemNotFound)
    let cookies = await api.checkoutCookies()
    XCTAssertTrue(cookies.isEmpty)
  }
  @MainActor
  func testGuestVerificationPersistsActualServiceExpiry() async throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }
    let quote = quoteEnding(in: 120)
    let actualEnd = try XCTUnwrap(quote.endDate).addingTimeInterval(45)
    let actualText = ISO8601DateFormatter().string(from: actualEnd)
    let response = try paidResponse(until: actualText)
    let id = UUID().uuidString
    GuestPaymentURLProtocol.register(id) { request in
      XCTAssertEqual(request.url?.path, "/payments/payg/calc")
      let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
      XCTAssertEqual(query?.first { $0.name == "step" }?.value, "1")
      XCTAssertEqual(query?.first { $0.name == "regplate" }?.value, "1234AA7")
      return .init(data: response)
    }
    defer { GuestPaymentURLProtocol.unregister(id) }
    let model = AppModel(
      defaults: fixture.defaults, storageURL: fixture.url,
      api: ParkoukaAPI(configuration: configuration(id), legacyCookieService: nil))

    XCTAssertTrue(model.begin(quote))
    await model.checkPayments()

    let confirmed = try XCTUnwrap(model.sessions.first)
    XCTAssertEqual(confirmed.state, .confirmed)
    XCTAssertEqual(confirmed.confirmationSource, .currentCoverage)
    XCTAssertEqual(confirmed.confirmedValidTill, actualText)
    XCTAssertEqual(confirmed.endDate, actualEnd)
    XCTAssertEqual(confirmed.quote, quote, "Verification must preserve the original quote and amount")
    let reopened = try LocalParkingStore(url: fixture.url)
    XCTAssertEqual(try reopened.load().sessions.first?.endDate, actualEnd)
    XCTAssertEqual(try reopened.load().sessions.first?.quote.amount, "2.0")
  }

  @MainActor
  func testClearingDataDuringVerificationCannotRestorePendingOrConfirmedHistory() async throws {
    let fixture = try Fixture()
    defer { fixture.cleanUp() }
    let quote = quoteEnding(in: 120)
    let response = try paidResponse(until: quote.validTill)
    let requested = expectation(description: "Coverage verification requested")
    let lateResponse = expectation(description: "Delayed server response released after reset")
    let id = UUID().uuidString
    GuestPaymentURLProtocol.register(id) { _ in
      requested.fulfill()
      return .init(data: response, delay: 0.3, attemptedDelivery: { lateResponse.fulfill() })
    }
    defer { GuestPaymentURLProtocol.unregister(id) }
    let model = AppModel(
      defaults: fixture.defaults, storageURL: fixture.url,
      api: ParkoukaAPI(configuration: configuration(id), legacyCookieService: nil))
    try await model.add(Vehicle(plate: "1234AA7", nickname: "Test car"))
    XCTAssertTrue(model.begin(quote))
    let checking = Task { await model.checkPayments() }
    await fulfillment(of: [requested], timeout: 5)

    await model.eraseLocalData()
    await checking.value
    await fulfillment(of: [lateResponse], timeout: 5)

    XCTAssertTrue(model.sessions.isEmpty)
    XCTAssertTrue(model.vehicles.isEmpty)
    XCTAssertNil(model.selectedVehicleID)
    XCTAssertNil(model.checkMessage, "A canceled old request must not repopulate status after erase")
    XCTAssertFalse(model.checking)
    let reopened = try LocalParkingStore(url: fixture.url)
    let persisted = try reopened.load()
    XCTAssertTrue(persisted.sessions.isEmpty)
    XCTAssertTrue(persisted.vehicles.isEmpty)
    XCTAssertNil(persisted.selectedVehicleID)
  }

  func testGuestCookieJarDropsOldCookiesAndTransfersOnlyCurrentMerchantCookies() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    let cookieJar = try XCTUnwrap(configuration.httpCookieStorage)
    let old = try cookie(name: "retired-session", domain: "parkouka.by")
    cookieJar.setCookie(old)
    let api = ParkoukaAPI(configuration: configuration, legacyCookieService: nil)
    let initial = await api.checkoutCookies()
    XCTAssertTrue(initial.isEmpty)

    let guest = try cookie(name: "guest-checkout", domain: "parkouka.by")
    let unrelated = try cookie(name: "unrelated", domain: "example.invalid")
    cookieJar.setCookie(guest)
    cookieJar.setCookie(unrelated)
    let transferable = await api.checkoutCookies()
    XCTAssertEqual(transferable.map(\.name), [guest.name])
    await api.resetGuestSession()
    let reset = await api.checkoutCookies()
    XCTAssertTrue(reset.isEmpty)
  }

  private func configuration(_ id: String) -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [GuestPaymentURLProtocol.self]
    configuration.httpAdditionalHeaders = [GuestPaymentURLProtocol.testHeader: id]
    return configuration
  }
  private func quoteEnding(in seconds: TimeInterval) -> ParkingQuote {
    let formatter = ISO8601DateFormatter()
    let now = Date()
    return ParkingQuote(
      plate: "1234AA7", zoneID: "710", zoneTitle: "Test parking",
      start: formatter.string(from: now.addingTimeInterval(-60)),
      validTill: formatter.string(from: now.addingTimeInterval(seconds)),
      hours: 1, isExtension: false, tariff: 1, amount: "2.0", eripURL: nil, createdAt: now)
  }
  private func paidResponse(until end: String) throws -> Data {
    try JSONSerialization.data(withJSONObject: [
      "status": "ok", "found": true, "t_start": end, "paid_dur": 3600,
      "hours_due": 1, "zone_type": 0, "tariff_modifier_id": 1,
    ])
  }
  private func cookie(name: String, domain: String) throws -> HTTPCookie {
    try XCTUnwrap(HTTPCookie(properties: [
      .name: name, .value: "fixture-only", .domain: domain, .path: "/", .secure: "TRUE",
    ]))
  }

  private struct Fixture {
    let directory: URL
    let url: URL
    let suite: String
    let defaults: UserDefaults
    init() throws {
      suite = "by.stajanka.guest-test.\(UUID())"
      directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      url = directory.appendingPathComponent("parking.sqlite")
      defaults = UserDefaults(suiteName: suite)!
    }
    func cleanUp() {
      defaults.removePersistentDomain(forName: suite)
      try? FileManager.default.removeItem(at: directory)
    }
  }
}

private final class GuestPaymentURLProtocol: URLProtocol {
  struct Response {
    let data: Data
    var delay: TimeInterval = 0
    var attemptedDelivery: (() -> Void)? = nil
  }
  static let testHeader = "X-Stajanka-Test-Request"
  private static let registryLock = NSLock()
  private static var responses: [String: (URLRequest) -> Response] = [:]
  private let deliveryLock = NSLock()
  private var stopped = false

  static func register(_ id: String, response: @escaping (URLRequest) -> Response) {
    registryLock.lock()
    defer { registryLock.unlock() }
    responses[id] = response
  }
  static func unregister(_ id: String) {
    registryLock.lock()
    defer { registryLock.unlock() }
    responses.removeValue(forKey: id)
  }
  override class func canInit(with request: URLRequest) -> Bool {
    request.value(forHTTPHeaderField: testHeader) != nil
  }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    Self.registryLock.lock()
    let handler = request.value(forHTTPHeaderField: Self.testHeader).flatMap { Self.responses[$0] }
    Self.registryLock.unlock()
    guard let handler else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }
    let response = handler(request)
    DispatchQueue.global().asyncAfter(deadline: .now() + response.delay) { [self] in
      deliveryLock.lock()
      let canDeliver = !stopped
      deliveryLock.unlock()
      if canDeliver {
        let http = HTTPURLResponse(
          url: request.url!, statusCode: 200, httpVersion: nil,
          headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.data)
        client?.urlProtocolDidFinishLoading(self)
      }
      response.attemptedDelivery?()
    }
  }
  override func stopLoading() {
    deliveryLock.lock()
    stopped = true
    deliveryLock.unlock()
  }
}
