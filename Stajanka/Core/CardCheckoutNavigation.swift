import Foundation

/// Return navigation must execute, but merchant documents must never be displayed.
/// A return is only a signal to verify coverage, never proof of successful payment.
struct CardCheckoutNavigation {
  enum Phase: Equatable { case preparing, bank, returning, finished, failed }
  private(set) var phase: Phase = .preparing
  private(set) var visitedProvider = false
  private(set) var returnStarted = false
  let merchantOrigin: URL
  let providerHost: String

  init(
    merchantOrigin: URL = URL(string: "https://parkouka.by")!,
    providerHost: String = "checkout.bepaid.by"
  ) {
    self.merchantOrigin = merchantOrigin
    self.providerHost = providerHost
  }
  func isMerchant(_ url: URL) -> Bool {
    url.scheme?.lowercased() == merchantOrigin.scheme?.lowercased()
      && url.host?.lowercased() == merchantOrigin.host?.lowercased()
      && (url.port ?? 443) == (merchantOrigin.port ?? 443)
      && url.user == nil && url.password == nil
  }
  mutating func willNavigate(to url: URL, mainFrame: Bool) {
    guard mainFrame, phase != .finished, phase != .failed else { return }
    if isMerchant(url) {
      if visitedProvider {
        returnStarted = true
        phase = .returning
      } else {
        phase = .preparing
      }
    }
  }
  mutating func committed(_ url: URL) {
    guard phase != .finished, phase != .failed else { return }
    if isMerchant(url) {
      willNavigate(to: url, mainFrame: true)
      return
    }
    if url.host?.lowercased() == providerHost && url.scheme == merchantOrigin.scheme {
      visitedProvider = true
    }
    if visitedProvider && !returnStarted { phase = .bank }
  }
  mutating func finished(_ url: URL) -> Bool {
    guard phase != .finished, phase != .failed, isMerchant(url) else { return false }
    if visitedProvider && returnStarted {
      phase = .finished
      return true
    }
    // An initial merchant document may still perform a JavaScript redirect.
    // Keep it concealed and let the startup timeout handle a genuinely stalled launch.
    return false
  }
  mutating func fail() { if phase != .finished { phase = .failed } }
  func mayDisplay(_ url: URL?) -> Bool {
    guard let url else { return false }
    return phase == .bank && !returnStarted && !isMerchant(url)
  }
}
