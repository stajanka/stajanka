import Foundation
import Security

enum ParkoukaError: LocalizedError {
  case message(String)
  var errorDescription: String? {
    if case .message(let s) = self { return s }
    return nil
  }
}

/// Uses only public map/payment endpoints with an in-memory guest cookie jar.
/// No vehicle ownership confirmation or violation endpoint is called.
actor ParkoukaAPI {
  static let shared = ParkoukaAPI()
  private var session: URLSession
  private let protocolClasses: [AnyClass]?
  private let legacyCookieService: String?
  init(
    configuration: URLSessionConfiguration = .ephemeral,
    legacyCookieService: String? = LegacyAccountSession.service
  ) {
    self.protocolClasses = configuration.protocolClasses
    self.legacyCookieService = legacyCookieService
    configuration.timeoutIntervalForRequest = 25
    configuration.httpCookieAcceptPolicy = .always
    configuration.httpCookieStorage?.removeCookies(since: .distantPast)
    session = URLSession(configuration: configuration)
    if let legacyCookieService { LegacyAccountSession.remove(service: legacyCookieService) }
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
    if response.url?.path.hasPrefix("/users/") == true {
      throw ParkoukaError.message(L("Сервис парковок временно недоступен. Попробуйте ещё раз."))
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
  func checkoutCookies() -> [HTTPCookie] {
    (session.configuration.httpCookieStorage?.cookies ?? []).filter {
      $0.domain == "parkouka.by" || $0.domain == ".parkouka.by"
    }
  }
  func resetGuestSession() {
    session.invalidateAndCancel()
    session.configuration.httpCookieStorage?.removeCookies(since: .distantPast)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = protocolClasses
    configuration.timeoutIntervalForRequest = 25
    configuration.httpCookieAcceptPolicy = .always
    session = URLSession(configuration: configuration)
    if let legacyCookieService { LegacyAccountSession.remove(service: legacyCookieService) }
  }
}

/// One-way cleanup of the retired login session; never reads or restores credentials.
enum LegacyAccountSession {
  static var service: String {
    AppPersistence.isUITest ? "by.stajanka.tests" : "by.stajanka.session"
  }
  static func remove(service: String) {
    SecItemDelete(
      [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: "cookies",
      ] as CFDictionary)
  }
}
