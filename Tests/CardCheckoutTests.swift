import WebKit
import XCTest

@testable import Stajanka

final class CardCheckoutTests: XCTestCase {
  private let merchant = URL(string: "https://parkouka.by/")!
  private let bank = URL(string: "https://checkout.bepaid.by/widget/hpp.html")!

  func testMerchantNeverDisplaysAtStartOrReturn() {
    var flow = CardCheckoutNavigation()
    flow.willNavigate(to: merchant, mainFrame: true)
    XCTAssertFalse(flow.mayDisplay(merchant))
    flow.committed(bank)
    XCTAssertTrue(flow.mayDisplay(bank))
    let callback = URL(string: "https://parkouka.by/payments/card/return?status=successful")!
    flow.willNavigate(to: callback, mainFrame: true)
    XCTAssertEqual(flow.phase, .returning)
    XCTAssertFalse(flow.mayDisplay(bank))
    XCTAssertFalse(flow.mayDisplay(callback))
    flow.committed(callback)
    XCTAssertTrue(flow.finished(merchant))
    XCTAssertFalse(flow.finished(merchant), "Return callback must be delivered once")
  }
  func testDeclinedReturnIsNotProofOfPayment() {
    var flow = CardCheckoutNavigation()
    flow.committed(bank)
    let failed = URL(string: "https://parkouka.by/?status=failed")!
    flow.willNavigate(to: failed, mainFrame: true)
    XCTAssertFalse(flow.mayDisplay(failed))
    XCTAssertTrue(flow.finished(failed), "Both results ask the native app to verify payment")
  }
  func testBankAuthenticationAndMerchantIframesDoNotCloseCheckout() {
    var flow = CardCheckoutNavigation()
    flow.committed(bank)
    flow.willNavigate(to: merchant, mainFrame: false)
    XCTAssertFalse(flow.returnStarted)
    let authentication = URL(string: "https://bank.example/3ds/challenge")!
    flow.committed(authentication)
    XCTAssertTrue(flow.mayDisplay(authentication))
    XCTAssertFalse(flow.finished(authentication))
  }
  func testLookalikeHostsAreNotMerchantCallbacks() {
    let flow = CardCheckoutNavigation()
    XCTAssertTrue(flow.isMerchant(URL(string: "https://parkouka.by:443/")!))
    for url in [
      "https://parkouka.by.evil.example/", "https://parkouka.by@evil.example/",
      "http://parkouka.by/",
    ] {
      XCTAssertFalse(flow.isMerchant(URL(string: url)!))
    }
  }
  func testStartupFailureAndNetworkErrorNeverDisplayMerchant() {
    var flow = CardCheckoutNavigation()
    XCTAssertFalse(flow.finished(merchant))
    XCTAssertEqual(flow.phase, .preparing)
    XCTAssertFalse(flow.mayDisplay(merchant))
    flow.fail()
    XCTAssertEqual(flow.phase, .failed)
    flow.committed(bank)
    XCTAssertFalse(flow.mayDisplay(bank))
  }

  @MainActor
  func testWebKitExecutesSuccessCallbackWithoutDisplayingMerchant() async throws {
    try await exerciseRealWebKitReturn(status: "successful")
  }
  @MainActor
  func testWebKitExecutesFailedCallbackWithoutDisplayingMerchant() async throws {
    try await exerciseRealWebKitReturn(status: "failed")
  }

  @MainActor
  private func exerciseRealWebKitReturn(status: String) async throws {
    // Real WKWebView and delegates, but all pages are local fixtures, with no invoice or charge.
    let origin = URL(string: "stajanka-fixture://merchant")!
    let configuration = WKWebViewConfiguration()
    let fixture = CheckoutFixture()
    configuration.setURLSchemeHandler(fixture, forURLScheme: "stajanka-fixture")
    let flow = CardCheckoutNavigation(merchantOrigin: origin, providerHost: "provider")
    let controller = CardCheckoutController(
      url: URL(string: "stajanka-fixture://merchant/start")!,
      cookies: [], flow: flow, configuration: configuration)
    let bankShown = expectation(description: "Bank form shown")
    let callbackHandled = expectation(description: "Merchant callback executed")
    let returned = expectation(description: "Native return")
    var directedReturn = false
    fixture.willServeMerchantCallback = {
      XCTAssertTrue(
        controller.webViews.allSatisfy(\.isHidden), "Hide before merchant response can paint")
      callbackHandled.fulfill()
    }
    controller.onPhase = { phase, _, error in
      if phase == .failed { XCTFail(error ?? "Unexpected failure") }
      if phase == .bank && !directedReturn {
        directedReturn = true
        XCTAssertFalse(controller.webViews[0].isHidden)
        bankShown.fulfill()
        controller.webViews[0].evaluateJavaScript(
          "location.href = 'stajanka-fixture://merchant/return?status=\(status)'",
          completionHandler: nil)
      }
    }
    controller.onReturn = {
      XCTAssertTrue(controller.webViews.allSatisfy(\.isHidden))
      XCTAssertEqual(controller.flow.phase, .finished)
      returned.fulfill()
    }
    let window = UIWindow(frame: UIScreen.main.bounds)
    window.rootViewController = controller
    window.isHidden = false
    controller.loadViewIfNeeded()
    defer {
      controller.stop()
      window.isHidden = true
    }
    await fulfillment(of: [bankShown, callbackHandled, returned], timeout: 20, enforceOrder: true)
  }
}

@MainActor
private final class CheckoutFixture: NSObject, WKURLSchemeHandler {
  var willServeMerchantCallback: (() -> Void)?
  func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
    let url = urlSchemeTask.request.url!
    let html: String
    if url.host == "merchant" && url.path == "/start" {
      html =
        "<html><body><script>location.replace('stajanka-fixture://provider/pay')</script></body></html>"
    } else if url.host == "provider" {
      html = "<html><body><h1>Test bank form</h1></body></html>"
    } else {
      willServeMerchantCallback?()
      html =
        "<html><body style='background:red'><h1>MERCHANT MUST NEVER BE VISIBLE</h1></body></html>"
    }
    let data = Data(html.utf8)
    urlSchemeTask.didReceive(
      URLResponse(
        url: url, mimeType: "text/html", expectedContentLength: data.count,
        textEncodingName: "utf-8"))
    urlSchemeTask.didReceive(data)
    urlSchemeTask.didFinish()
  }
  func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
