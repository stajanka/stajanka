import SwiftUI
import WebKit

struct CardCheckoutView: View {
  @Environment(\.dismiss) private var dismiss
  let url: URL
  let cookies: [HTTPCookie]
  let onReturn: () -> Void
  @State private var phase: CardCheckoutNavigation.Phase = .preparing
  @State private var host = "checkout.bepaid.by"
  @State private var failure: String?

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        Image(systemName: "lock.shield").foregroundStyle(Palette.green)
        VStack(alignment: .leading, spacing: 3) {
          Text(L("Оплата картой")).font(.headline)
          Text(host).font(.caption).foregroundStyle(Palette.muted).lineLimit(1)
        }
        Spacer()
        Button {
          dismiss()
        } label: {
          Image(systemName: "xmark").font(.system(size: 14, weight: .bold))
            .frame(width: 40, height: 40).background(.white, in: Circle())
        }.accessibilityLabel(L("Закрыть оплату"))
      }.padding(18).background(Palette.paper)
      ZStack {
        CardCheckoutWebView(
          url: url, cookies: cookies,
          onPhase: { value, hostname, error in
            phase = value
            if let hostname, value == .bank { host = hostname }
            failure = error
          }, onReturn: onReturn)
        if phase != .bank {
          VStack(spacing: 18) {
            if phase == .failed {
              Image(systemName: "wifi.exclamationmark").font(.largeTitle)
              Text(L("Не удалось завершить переход")).font(.title3.bold())
              Text(failure ?? L("Закройте окно — Стаянка проверит, зарегистрирована ли оплата."))
                .font(.subheadline).foregroundStyle(Palette.muted)
              Button(L("Закрыть и проверить")) { dismiss() }.font(.headline)
            } else {
              ProgressView().tint(Palette.green).scaleEffect(1.3)
              Text(
                phase == .preparing ? L("Открываем защищённую форму") : L("Возвращаемся в Стаянку")
              )
              .font(.headline)
              Text(
                phase == .preparing
                  ? L("Данные карты вводятся на странице банка.")
                  : L("Дождёмся регистрации платежа и проверим оплаченное время.")
              )
              .font(.subheadline).foregroundStyle(Palette.muted)
            }
          }.multilineTextAlignment(.center).padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.paper)
            .accessibilityIdentifier("card-native-overlay")
        }
      }
    }.foregroundStyle(Palette.ink).background(Palette.paper)
  }
}

struct CardCheckoutWebView: UIViewControllerRepresentable {
  let url: URL
  let cookies: [HTTPCookie]
  let onPhase: (CardCheckoutNavigation.Phase, String?, String?) -> Void
  let onReturn: () -> Void
  func makeUIViewController(context: Context) -> CardCheckoutController {
    let controller = CardCheckoutController(url: url, cookies: cookies)
    controller.onPhase = onPhase
    controller.onReturn = onReturn
    return controller
  }
  func updateUIViewController(_ controller: CardCheckoutController, context: Context) {}
  static func dismantleUIViewController(_ controller: CardCheckoutController, coordinator: ()) {
    controller.stop()
  }
}

@MainActor
final class CardCheckoutController: UIViewController, WKNavigationDelegate, WKUIDelegate {
  private let startURL: URL
  private let cookies: [HTTPCookie]
  private let suppliedConfiguration: WKWebViewConfiguration?
  private(set) var flow: CardCheckoutNavigation
  private(set) var webViews: [WKWebView] = []
  var onPhase: ((CardCheckoutNavigation.Phase, String?, String?) -> Void)?
  var onReturn: (() -> Void)?
  private var timeout: Task<Void, Never>?
  private var startup: Task<Void, Never>?
  private var stopped = false

  init(
    url: URL, cookies: [HTTPCookie], flow: CardCheckoutNavigation = .init(),
    configuration: WKWebViewConfiguration? = nil
  ) {
    startURL = url
    self.cookies = cookies
    self.flow = flow
    suppliedConfiguration = configuration
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { fatalError("Use init(url:cookies:)") }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = UIColor(Palette.paper)
    let configuration = suppliedConfiguration ?? WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    // No injected scripts or message handlers on payment/bank pages.
    let webView = makeWebView(configuration: configuration)
    startup = Task { [weak self, weak webView] in
      guard let self, let webView else { return }
      for cookie in cookies {
        await configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
      }
      guard !Task.isCancelled, !stopped else { return }
      webView.load(URLRequest(url: startURL))
      armTimeout()
    }
  }
  private func makeWebView(configuration: WKWebViewConfiguration) -> WKWebView {
    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.isHidden = true
    webView.navigationDelegate = self
    webView.uiDelegate = self
    webView.isOpaque = false
    webView.backgroundColor = UIColor(Palette.paper)
    webView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(webView)
    NSLayoutConstraint.activate([
      webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      webView.topAnchor.constraint(equalTo: view.topAnchor),
      webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
    webViews.append(webView)
    return webView
  }
  func stop() {
    stopped = true
    startup?.cancel()
    timeout?.cancel()
    for webView in webViews {
      webView.stopLoading()
      webView.navigationDelegate = nil
      webView.uiDelegate = nil
    }
  }
  private func publish(_ error: String? = nil) {
    let phase = flow.phase
    let host = webViews.last?.url?.host
    // SwiftUI gets the phase on the next turn; UIKit visibility is changed synchronously below.
    DispatchQueue.main.async { [weak self] in
      guard let self, !stopped else { return }
      onPhase?(phase, host, error)
    }
  }
  private func conceal() { for view in webViews { view.isHidden = true } }
  private func armTimeout() {
    timeout?.cancel()
    timeout = Task { [weak self] in
      do { try await Task.sleep(for: .seconds(40)) } catch { return }
      guard let self, flow.phase == .preparing || flow.phase == .returning else { return }
      fail(L("Сервис долго отвечает. Закройте окно и проверьте оплату в Стаянке."))
    }
  }
  private func fail(_ message: String) {
    timeout?.cancel()
    flow.fail()
    conceal()
    publish(message)
  }
  func handleNavigation(to url: URL, mainFrame: Bool) {
    let wasReturning = flow.returnStarted
    flow.willNavigate(to: url, mainFrame: mainFrame)
    if mainFrame && (flow.isMerchant(url) || flow.returnStarted) {
      // Runs before decisionHandler(.allow), including server redirect responses.
      conceal()
      if flow.returnStarted && !wasReturning { armTimeout() }
      publish()
    }
  }
  func webView(
    _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
  ) {
    guard let url = action.request.url else {
      decisionHandler(.cancel)
      return
    }
    let main = action.targetFrame?.isMainFrame ?? true
    handleNavigation(to: url, mainFrame: main)
    if ["https", "about"].contains(url.scheme ?? "") || url.scheme == flow.merchantOrigin.scheme {
      decisionHandler(.allow)
    } else {
      // Hand off explicitly clicked bank-app links; never run arbitrary automatic custom schemes.
      if main, action.navigationType == .linkActivated, flow.visitedProvider {
        UIApplication.shared.open(url)
      }
      decisionHandler(.cancel)
    }
  }
  func webView(
    _ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
    decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
  ) {
    if response.isForMainFrame, let url = response.response.url,
      url.scheme != "https" && url.scheme != flow.merchantOrigin.scheme && url.scheme != "about"
    {
      fail(L("Банк вернул неподдерживаемый адрес. Проверьте результат оплаты в Стаянке."))
      decisionHandler(.cancel)
      return
    }
    if let url = response.response.url {
      handleNavigation(to: url, mainFrame: response.isForMainFrame)
    }
    // Merchant callback must execute. Hiding is not cancellation.
    decisionHandler(.allow)
  }
  func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
    guard let url = webView.url else { return }
    flow.committed(url)
    if flow.mayDisplay(url) {
      timeout?.cancel()
      for other in webViews { other.isHidden = other !== webView }
    } else {
      conceal()
    }
    publish()
  }
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    guard let url = webView.url else { return }
    if flow.finished(url) {
      timeout?.cancel()
      conceal()
      publish()
      onReturn?()
    } else if flow.phase == .failed {
      fail(L("Сервис не открыл банковскую форму. Закройте окно и проверьте состояние парковки."))
    }
  }
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    navigationFailed(error)
  }
  func webView(
    _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) {
    navigationFailed(error)
  }
  private func navigationFailed(_ error: Error) {
    if (error as NSError).code == NSURLErrorCancelled { return }
    fail(L("Не удалось загрузить страницу. Результат оплаты проверим отдельно."))
  }
  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    fail(L("Банковское окно было закрыто системой. Проверьте результат оплаты."))
  }
  func webView(
    _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
    for action: WKNavigationAction, windowFeatures: WKWindowFeatures
  ) -> WKWebView? {
    guard action.targetFrame == nil else { return nil }
    // Preserve opener semantics and WebKit's supplied configuration for 3-D Secure windows.
    let popup = makeWebView(configuration: configuration)
    if let url = action.request.url { handleNavigation(to: url, mainFrame: true) }
    return popup
  }
  func webViewDidClose(_ webView: WKWebView) {
    guard webViews.count > 1 else { return }
    webView.navigationDelegate = nil
    webView.uiDelegate = nil
    webView.removeFromSuperview()
    webViews.removeAll { $0 === webView }
    if let previous = webViews.last { previous.isHidden = !flow.mayDisplay(previous.url) }
  }
}
