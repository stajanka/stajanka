import Foundation
import Security

enum ParkoukaError: LocalizedError {
  case message(String)
  var errorDescription: String? {
    if case .message(let s) = self { return s }
    return nil
  }
}

/// Uses only public map/payment endpoints and the account's parking history.
/// No vehicle ownership confirmation or violation endpoint is called.
actor ParkoukaAPI {
  static let shared = ParkoukaAPI()
  private let session: URLSession
  init() {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 25
    configuration.httpCookieAcceptPolicy = .always
    session = URLSession(configuration: configuration)
    if let saved = Keychain.read("cookies"),
      let dictionaries = try? JSONSerialization.jsonObject(with: saved) as? [[String: String]]
    {
      for dict in dictionaries {
        let properties = Dictionary(
          uniqueKeysWithValues: dict.map { (HTTPCookiePropertyKey($0.key), $0.value) })
        if let cookie = HTTPCookie(properties: properties) {
          configuration.httpCookieStorage?.setCookie(cookie)
        }
      }
    }
  }
  private func get(_ path: String, query: [URLQueryItem] = []) async throws -> Data {
    var request = URLRequest(
      url: ParkingQuote.url(path: path, query: query), cachePolicy: .reloadIgnoringLocalCacheData)
    request.setValue("application/json, text/html", forHTTPHeaderField: "Accept")
    request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
    return try await perform(request)
  }
  private func perform(_ request: URLRequest) async throws -> Data {
    let (data, response) = try await session.data(for: request)
    guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode)
    else {
      throw ParkoukaError.message(L("Сервис парковок временно недоступен. Попробуйте ещё раз."))
    }
    if response.url?.path == "/users/sign_in", request.url?.path != "/users/sign_in" {
      throw ParkoukaError.message(L("Войдите в кабинет, чтобы увидеть историю оплат."))
    }
    return data
  }
  func zones() async throws -> [ParkingZone] {
    let data = try await get("/")
    guard let html = String(data: data, encoding: .utf8), let marker = html.range(of: "zonesHash:")
    else { throw ParkoukaError.message(L("Не удалось обновить карту парковок.")) }
    let tail = html[marker.upperBound...]
    guard let first = tail.firstIndex(of: "{") else {
      throw ParkoukaError.message(L("Формат карты изменился."))
    }
    var depth = 0
    var inString = false
    var escaped = false
    for i in tail[first...].indices {
      let c = tail[i]
      if escaped {
        escaped = false
        continue
      }
      if c == "\\" && inString {
        escaped = true
        continue
      }
      if c == "\"" { inString.toggle() }
      if !inString {
        if c == "{" { depth += 1 }
        if c == "}" {
          depth -= 1
          if depth == 0 { return try ParkingZone.decode(Data(tail[first...i].utf8)) }
        }
      }
    }
    throw ParkoukaError.message(L("Формат карты изменился."))
  }
  func start(plate: String, zoneID: String, tariff: Int = 1) async throws -> StartResponse {
    let q = ["step": "1", "regplate": plate, "zid": zoneID, "tmid": String(tariff)].map {
      URLQueryItem(name: $0.key, value: $0.value)
    }
    let response = try JSONDecoder().decode(
      StartResponse.self, from: await get("/payments/payg/calc", query: q))
    guard response.status == "ok" else {
      throw ParkoukaError.message(
        response.details == "BUS"
          ? L("Для этого номера нужен тариф автобуса. Измените тип автомобиля.")
          : response.details ?? L("Не удалось рассчитать парковку."))
    }
    return response
  }
  func quote(vehicle: Vehicle, zone: ParkingZone, hours: Int) async throws -> ParkingQuote {
    let first = try await start(
      plate: vehicle.plate, zoneID: zone.paymentID, tariff: vehicle.isBus ? 2 : 1)
    guard let start = first.t_start else {
      throw ParkoukaError.message(L("Сервис не вернул время начала парковки."))
    }
    let duration = first.zone_type == 1 && first.found == true ? (first.hours_due ?? hours) : hours
    let tariff = first.tariff_modifier_id ?? (vehicle.isBus ? 2 : 1)
    let q = [
      "step": "2", "regplate": vehicle.plate, "zid": zone.paymentID, "t_start": start,
      "hrs": String(duration), "ext": first.isExtension ? "1" : "0", "tmid": String(tariff),
    ].map { URLQueryItem(name: $0.key, value: $0.value) }
    let second = try JSONDecoder().decode(
      QuoteResponse.self, from: await get("/payments/payg/calc", query: q))
    guard second.status == "ok", let amount = second.amount, let till = second.valid_till else {
      throw ParkoukaError.message(second.details ?? L("Не удалось получить стоимость."))
    }
    return ParkingQuote(
      plate: vehicle.plate, zoneID: zone.paymentID, zoneTitle: zone.title, start: start,
      validTill: till, hours: duration, isExtension: first.isExtension, tariff: tariff,
      amount: amount, eripURL: second.erip_url, createdAt: Date(), countryCode: vehicle.countryCode)
  }
  func login(email: String, password: String) async throws {
    let html = String(decoding: try await get("/users/sign_in"), as: UTF8.self)
    guard let token = capture("name=\"authenticity_token\" value=\"([^\"]+)\"", in: html) else {
      throw ParkoukaError.message(L("Форма входа изменилась."))
    }
    var request = URLRequest(url: URL(string: "https://parkouka.by/users/sign_in")!)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.setValue("https://parkouka.by/users/sign_in", forHTTPHeaderField: "Referer")
    request.httpBody = form([
      "authenticity_token": token, "user[email]": email, "user[password]": password,
      "user[remember_me]": "1",
    ])
    let result = String(decoding: try await perform(request), as: UTF8.self)
    guard !result.contains("id=\"new_user\"") else {
      throw ParkoukaError.message(L("Не удалось войти. Проверьте почту и пароль."))
    }
    saveCookies()
  }
  func history() async throws -> [HistoryRow] {
    let data = try await get(
      "/account/parking_sessions",
      query: [
        URLQueryItem(name: "current", value: "1"), URLQueryItem(name: "rowCount", value: "50"),
        URLQueryItem(name: "sort[valid_till]", value: "desc"),
      ])
    return try JSONDecoder().decode(HistoryResponse.self, from: data).rows
  }
  func checkoutCookies() -> [HTTPCookie] {
    (session.configuration.httpCookieStorage?.cookies ?? []).filter {
      $0.domain == "parkouka.by" || $0.domain == ".parkouka.by"
    }
  }
  func registerVehicle(_ vehicle: Vehicle) async throws {
    let html = String(decoding: try await get("/vehicles/add"), as: UTF8.self)
    guard let token = capture("name=\"csrf-token\" content=\"([^\"]+)\"", in: html) else {
      throw ParkoukaError.message(L("Сначала войдите в кабинет."))
    }
    var r = URLRequest(url: URL(string: "https://parkouka.by/vehicles/add")!)
    r.httpMethod = "POST"
    r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    r.setValue(token, forHTTPHeaderField: "X-CSRF-Token")
    r.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
    // Intentionally omit doc_number, owner_name, pp_consent and all confirmation fields.
    r.httpBody = form(["regplate": vehicle.plate, "veh_type": vehicle.isBus ? "3" : "1"])
    let result = try JSONDecoder().decode(QuoteResponse.self, from: await perform(r))
    guard result.status == "OK" else {
      throw ParkoukaError.message(result.details ?? L("Не удалось добавить автомобиль в кабинет."))
    }
    saveCookies()
  }
  func logout() {
    session.configuration.httpCookieStorage?.removeCookies(since: .distantPast)
    Keychain.remove("cookies")
  }
  private func saveCookies() {
    let cookies = session.configuration.httpCookieStorage?.cookies ?? []
    let values = cookies.filter { $0.domain.contains("parkouka.by") }.map { c in
      ["Name": c.name, "Value": c.value, "Domain": c.domain, "Path": c.path, "Secure": "TRUE"]
    }
    if let data = try? JSONSerialization.data(withJSONObject: values) {
      Keychain.write(data, key: "cookies")
    }
  }
  private func capture(_ pattern: String, in text: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern),
      let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
      let r = Range(m.range(at: 1), in: text)
    else { return nil }
    return String(text[r])
  }
  private func form(_ fields: [String: String]) -> Data {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
    return Data(
      fields.map {
        "\($0.key.addingPercentEncoding(withAllowedCharacters:allowed)!)=\($0.value.addingPercentEncoding(withAllowedCharacters:allowed)!)"
      }.joined(separator: "&").utf8)
  }
}

enum Keychain {
  static func base(_ key: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: AppPersistence.isUITest
        ? "by.stajanka.tests" : "by.stajanka.session", kSecAttrAccount as String: key,
    ]
  }
  static func write(_ data: Data, key: String) {
    remove(key)
    var q = base(key)
    q[kSecValueData as String] = data
    q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    SecItemAdd(q as CFDictionary, nil)
  }
  static func read(_ key: String) -> Data? {
    var q = base(key)
    q[kSecReturnData as String] = true
    var result: CFTypeRef?
    guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess else { return nil }
    return result as? Data
  }
  static func remove(_ key: String) { SecItemDelete(base(key) as CFDictionary) }
}
