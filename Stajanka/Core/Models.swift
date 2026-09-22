import CoreLocation
import Foundation

struct ParkingZone: Decodable, Identifiable {
  var id: String = ""
  let name: String
  let hours: String
  let cost: String
  let map: [[[Double]]]
  let windowPos: [[Double]]
  let launch_date: String?
  let zone_type: Int
  let parent_zone: String?
  let parent_zone_id: Int?
  enum CodingKeys: String, CodingKey {
    case name, hours, cost, map, windowPos, launch_date, zone_type, parent_zone, parent_zone_id
  }
  var title: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
  var displayCost: String {
    if cost == "Первый час 7 руб, затем 3 руб/час" { return L("Первый час 7 руб, затем 3 руб/час") }
    return cost.replacingOccurrences(of: "руб/час", with: L("руб/час"))
  }
  var displayHours: String {
    let value = hours.trimmingCharacters(in: .whitespaces)
    return value == "24ч" ? L("24ч") : value
  }
  var paymentID: String { parent_zone_id.map(String.init) ?? id }
  var number: String { parent_zone ?? id }
  var coordinate: CLLocationCoordinate2D {
    let p = windowPos.first ?? map.first?.first ?? [53.9023, 27.5619]
    return .init(latitude: p[0], longitude: p[1])
  }
  var polygons: [[CLLocationCoordinate2D]] {
    map.map { $0.filter { $0.count >= 2 }.map { .init(latitude: $0[0], longitude: $0[1]) } }
  }
  static func decode(_ data: Data) throws -> [ParkingZone] {
    try JSONDecoder().decode([String: ParkingZone].self, from: data).map { key, value in
      var zone = value
      zone.id = key
      return zone
    }.sorted { $0.title < $1.title }
  }
}

struct Vehicle: Codable, Identifiable, Equatable {
  var id: UUID = UUID()
  var plate: String
  var nickname: String
  var isBus: Bool = false
  var countryCode: String = "BY"
  var label: String {
    let name = Self.cleanNickname(nickname)
    return name.isEmpty ? L("Мой автомобиль") : name
  }
  static func cleanNickname(_ value: String) -> String {
    String(value.prefix(40)).components(separatedBy: .newlines).joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
  static func normalize(_ text: String) -> String {
    let replacements: [Character: Character] = [
      "А": "A", "В": "B", "Е": "E", "К": "K", "М": "M", "Н": "H", "О": "O", "Р": "P", "С": "C",
      "Т": "T", "У": "Y", "Х": "X", "І": "I",
    ]
    return String(
      text.uppercased().filter { !$0.isWhitespace && $0 != "-" }.map { replacements[$0] ?? $0 })
  }
  static func isValid(_ plate: String) -> Bool {
    normalize(plate).range(of: "^[A-Z0-9]{3,12}$", options: .regularExpression) != nil
  }
}

extension Vehicle {
  enum CodingKeys: String, CodingKey { case id, plate, nickname, isBus, countryCode }
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try values.decode(UUID.self, forKey: .id),
      plate: try values.decode(String.self, forKey: .plate),
      nickname: try values.decode(String.self, forKey: .nickname),
      isBus: try values.decodeIfPresent(Bool.self, forKey: .isBus) ?? false,
      countryCode: try values.decodeIfPresent(String.self, forKey: .countryCode) ?? "BY")
  }
}

struct StartResponse: Decodable {
  let status: String
  let details: String?
  let t_start: String?
  let found: Bool?
  let paid_dur: Double?
  let hours_due: Int?
  let zone_type: Int?
  let tariff_modifier_id: Int?
  let erip_tree_path: String?
  var isExtension: Bool { found == true && (zone_type == 0 || (paid_dur ?? 0) > 0) }
}
struct QuoteResponse: Decodable {
  let status: String
  let details: String?
  let valid_till: String?
  let amount: String?
  let erip_url: String?
}
struct ParkingQuote: Codable, Equatable {
  let plate: String
  let zoneID: String
  let zoneTitle: String
  let start: String
  let validTill: String
  let hours: Int
  let isExtension: Bool
  let tariff: Int
  let amount: String
  let eripURL: String?
  let createdAt: Date
  var countryCode: String? = nil
  var displayZoneTitle: String { amount.isEmpty ? L("Парковочная зона %@", zoneID) : zoneTitle }
  var endDate: Date? { ParkingDate.parse(validTill) }
  var amountLabel: String {
    amount.isEmpty ? L("Оплачено ранее") : L10n.money(amount)
  }
  var query: [URLQueryItem] {
    [
      "regplate": plate, "zid": zoneID, "t_start": start, "hrs": String(hours),
      "ext": isExtension ? "1" : "0", "tmid": String(tariff),
    ]
    .sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
  }
  var cardURL: URL { Self.url(path: "/payments/card/start_payment", query: query) }
  static func url(path: String, query: [URLQueryItem]) -> URL {
    var c = URLComponents(string: "https://parkouka.by")!
    c.path = path
    c.queryItems = query
    // A literal '+' must survive Rails form/query decoding as a timezone sign.
    c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
    return c.url!
  }
  func isCovered(by response: StartResponse, checkedAt: Date) -> Bool {
    guard response.status == "ok", response.isExtension,
      let paidUntil = response.t_start.flatMap(ParkingDate.parse), let expected = endDate,
      let originalStart = ParkingDate.parse(start), expected > checkedAt
    else { return false }
    // Existing coverage before checkout must never confirm a new extension.
    return paidUntil >= expected.addingTimeInterval(-1)
      && paidUntil > originalStart.addingTimeInterval(1)
  }
}

enum ParkingDate {
  static func parse(_ text: String) -> Date? {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.date(from: text) ?? ISO8601DateFormatter().date(from: text)
  }
  static func time(_ date: Date) -> String {
    let f = DateFormatter()
    f.locale = L10n.locale
    f.timeZone = TimeZone(identifier: "Europe/Minsk")
    f.dateFormat = "HH:mm"
    return f.string(from: date)
  }
}

struct ParkingSession: Codable, Identifiable {
  var id = UUID()
  let quote: ParkingQuote
  var state: State
  var lastChecked: Date?
  var confirmationSource: ConfirmationSource?
  var historyRowID: Int?
  var confirmedValidTill: String?
  var endDate: Date? { confirmedValidTill.flatMap(ParkingDate.parse) ?? quote.endDate }
  static func restored(vehicle: Vehicle, zone: ParkingZone, response: StartResponse, now: Date)
    -> ParkingSession?
  {
    guard response.status == "ok", response.isExtension,
      let till = response.t_start, let end = ParkingDate.parse(till), end > now,
      let duration = response.paid_dur, duration > 0
    else { return nil }
    let start = ISO8601DateFormatter().string(from: end.addingTimeInterval(-duration))
    let quote = ParkingQuote(
      plate: vehicle.plate, zoneID: zone.paymentID,
      zoneTitle: L("Парковочная зона %@", String(describing: zone.number)),
      start: start, validTill: till, hours: Int(ceil(duration / 3600)), isExtension: true,
      tariff: response.tariff_modifier_id ?? (vehicle.isBus ? 2 : 1), amount: "", eripURL: nil,
      createdAt: now, countryCode: vehicle.countryCode)
    return ParkingSession(
      quote: quote, state: .confirmed, lastChecked: now,
      confirmationSource: .currentCoverage, confirmedValidTill: till)
  }
  enum State: String, Codable { case awaiting, confirmed }
  enum ConfirmationSource: String, Codable { case currentCoverage, accountHistory }
}

struct HistoryResponse: Decodable {
  let rows: [HistoryRow]
  let total: Int
}
struct HistoryRow: Decodable, Identifiable {
  let id: Int
  let regplate_full: String
  let name: String
  let starts_at: String
  let valid_till: String
  let amount: String
  let parent_zone_id: Int?

  enum CodingKeys: String, CodingKey {
    case id, regplate_full, name, starts_at, valid_till, amount, parent_zone_id
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(Int.self, forKey: .id)
    regplate_full = try values.decode(String.self, forKey: .regplate_full)
    name = try values.decode(String.self, forKey: .name)
    starts_at = try values.decode(String.self, forKey: .starts_at)
    valid_till = try values.decode(String.self, forKey: .valid_till)
    if let text = try? values.decode(String.self, forKey: .amount) {
      amount = text
    } else {
      amount =
        NSDecimalNumber(decimal: try values.decode(Decimal.self, forKey: .amount)).stringValue
    }
    parent_zone_id = try values.decodeIfPresent(Int.self, forKey: .parent_zone_id)
  }

  /// Only exact period, vehicle, zone and amount matches corroborate a quote.
  /// Unrecognized date formats or missing zone identity never prove payment.
  func matches(_ quote: ParkingQuote) -> Bool {
    let matchesZone =
      parent_zone_id.map { String($0) == quote.zoneID }
      ?? (name == quote.zoneTitle)
    guard Vehicle.normalize(regplate_full) == quote.plate,
      matchesZone,
      let start = ParkingDate.parse(starts_at), let end = ParkingDate.parse(valid_till),
      let expectedStart = ParkingDate.parse(quote.start), let expectedEnd = quote.endDate,
      let value = Decimal(string: amount), let expectedAmount = Decimal(string: quote.amount),
      value == expectedAmount
    else { return false }
    return abs(start.timeIntervalSince(expectedStart)) < 1
      && abs(end.timeIntervalSince(expectedEnd)) < 1
  }
}
