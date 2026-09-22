import CoreLocation
import SwiftUI
import UserNotifications

enum AppPersistence {
  #if DEBUG
    static let isUITest = ProcessInfo.processInfo.arguments.contains("--ui-testing")
  #else
    static let isUITest = false
  #endif
  static let defaults: UserDefaults = {
    if isUITest {
      let suite = "by.stajanka.ui-tests"
      let defaults = UserDefaults(suiteName: suite)!
      if ProcessInfo.processInfo.arguments.contains("--reset-test-state") {
        defaults.removePersistentDomain(forName: suite)
      }
      return defaults
    }
    return .standard
  }()
}

@MainActor
final class AppModel: ObservableObject {
  private let defaults: UserDefaults
  private var dataRevision = UUID()
  @Published var zones: [ParkingZone] = []
  @Published var vehicles: [Vehicle] = [] { didSet { persist(vehicles, key: "vehicles") } }
  @Published var selectedVehicleID: UUID? {
    didSet { defaults.set(selectedVehicleID?.uuidString, forKey: "selectedVehicle") }
  }
  @Published var sessions: [ParkingSession] = [] { didSet { persist(sessions, key: "sessions") } }
  @Published var zoneMessage: String?
  @Published var refreshing = false
  @Published var loggedIn = Keychain.read("cookies") != nil
  @Published var history: [HistoryRow] = []
  @Published var checking = false
  @Published var checkMessage: String?
  @Published var accountCheckMessage: String?
  @Published var selectedZone: ParkingZone?
  private var didLoad = false
  private var restoringVehicles: Set<UUID> = []
  let api = ParkoukaAPI.shared
  var vehicle: Vehicle? { vehicles.first { $0.id == selectedVehicleID } ?? vehicles.first }
  var pending: [ParkingSession] { sessions.filter { $0.state == .awaiting } }
  var active: [ParkingSession] {
    sessions.filter { $0.state == .confirmed && ($0.endDate ?? .distantPast) > Date() }
  }
  init(defaults: UserDefaults = AppPersistence.defaults) {
    self.defaults = defaults
    let d = defaults
    vehicles = Self.restore([Vehicle].self, key: "vehicles", defaults: d) ?? []
    sessions = Self.restore([ParkingSession].self, key: "sessions", defaults: d) ?? []
    selectedVehicleID = d.string(forKey: "selectedVehicle").flatMap(UUID.init(uuidString:))
    if let url = Bundle.main.url(forResource: "zones", withExtension: "json"),
      let data = try? Data(contentsOf: url)
    {
      zones = (try? ParkingZone.decode(data)) ?? []
    }
    #if DEBUG
      if ScreenshotScenario.enabled { ScreenshotScenario.seed(self) }
    #endif
  }
  var isScreenshotSession: Bool {
    #if DEBUG
      return ScreenshotScenario.enabled
    #else
      return false
    #endif
  }
  func parkingQuote(vehicle: Vehicle, zone: ParkingZone, hours: Int) async throws -> ParkingQuote {
    #if DEBUG
      if ScreenshotScenario.enabled {
        return ScreenshotScenario.quote(vehicle: vehicle, zone: zone, hours: hours)
      }
    #endif
    return try await api.quote(vehicle: vehicle, zone: zone, hours: hours)
  }
  func load() async {
    guard !didLoad else { return }
    didLoad = true
    await refreshZones()
  }
  func refreshZones() async {
    if isScreenshotSession { return }
    refreshing = true
    defer { refreshing = false }
    do {
      zones = try await api.zones()
      zoneMessage = nil
    } catch {
      zoneMessage = L("Карта из сохранённой копии. Для актуальных условий обновите данные.")
    }
  }
  func add(_ vehicle: Vehicle, sync: Bool) async throws {
    var vehicle = vehicle
    vehicle.nickname = Vehicle.cleanNickname(vehicle.nickname)
    guard !vehicles.contains(where: { $0.plate == vehicle.plate }) else {
      throw ParkoukaError.message(L("Этот автомобиль уже добавлен."))
    }
    if sync { try await api.registerVehicle(vehicle) }
    vehicles.append(vehicle)
    selectedVehicleID = vehicle.id
  }
  func begin(_ quote: ParkingQuote) {
    if !sessions.contains(where: { $0.quote == quote }) {
      sessions.insert(ParkingSession(quote: quote, state: .awaiting), at: 0)
    }
  }
  func removeVehicle(_ vehicle: Vehicle) {
    vehicles.removeAll { $0.id == vehicle.id }
    if selectedVehicleID == vehicle.id || !vehicles.contains(where: { $0.id == selectedVehicleID })
    {
      selectedVehicleID = vehicles.first?.id
    }
    // A garage deletion does not cancel parking, erase receipts, or issue a refund.
  }
  func eraseLocalData() async {
    dataRevision = UUID()
    vehicles = []
    sessions = []
    selectedVehicleID = nil
    history = []
    checkMessage = nil
    accountCheckMessage = nil
    loggedIn = false
    UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    await api.logout()
  }
  /// Restores externally paid sessions using the six distinct payment-zone IDs,
  /// rather than guessing a particular street or a payment amount.
  func restoreCurrentParking() async {
    if isScreenshotSession { return }
    guard let vehicle, !restoringVehicles.contains(vehicle.id) else { return }
    restoringVehicles.insert(vehicle.id)
    defer { restoringVehicles.remove(vehicle.id) }
    let paymentZones = Dictionary(grouping: zones, by: \.paymentID).compactMap { $0.value.first }
    for zone in paymentZones {
      guard !Task.isCancelled, self.vehicle?.id == vehicle.id else { return }
      // Pending checkouts retain their own confirmation target.
      if pending.contains(where: {
        $0.quote.plate == vehicle.plate && $0.quote.zoneID == zone.paymentID
      }) {
        continue
      }
      do {
        let status = try await api.start(
          plate: vehicle.plate, zoneID: zone.paymentID,
          tariff: vehicle.isBus ? 2 : 1)
        guard !Task.isCancelled, self.vehicle?.id == vehicle.id,
          let restored = ParkingSession.restored(
            vehicle: vehicle, zone: zone, response: status, now: Date())
        else { continue }
        if let index = sessions.firstIndex(where: {
          $0.state == .confirmed && $0.quote.plate == vehicle.plate
            && $0.quote.zoneID == zone.paymentID
            && ($0.endDate ?? .distantPast) > Date()
        }) {
          sessions[index].confirmedValidTill = restored.confirmedValidTill
          sessions[index].lastChecked = restored.lastChecked
        } else {
          sessions.insert(restored, at: 0)
        }
      } catch {
        checkMessage =
          L("Не все зоны удалось проверить. Потяните список парковок вниз, чтобы повторить.")
      }
    }
  }
  func checkPayments() async {
    guard !checking, !pending.isEmpty else { return }
    checking = true
    defer { checking = false }
    let revision = dataRevision
    var errors: [String] = []
    var confirmed = 0
    var accountRows: [HistoryRow] = []
    accountCheckMessage = nil
    if loggedIn {
      do {
        accountRows = try await api.history()
        guard revision == dataRevision else { return }
        history = accountRows
      } catch {
        accountCheckMessage = L(
          "История кабинета недоступна: %@", String(describing: error.localizedDescription))
      }
    }
    for entry in pending {
      do {
        if let match = accountRows.first(where: { $0.matches(entry.quote) }),
          let i = sessions.firstIndex(where: { $0.id == entry.id })
        {
          sessions[i].state = .confirmed
          sessions[i].confirmationSource = .accountHistory
          sessions[i].historyRowID = match.id
          sessions[i].confirmedValidTill = match.valid_till
          sessions[i].lastChecked = Date()
          confirmed += 1
          await scheduleReminder(for: sessions[i])
          continue
        }
        // Current coverage cannot establish whether a past period was paid.
        // An old attempt requires a matching account record instead.
        guard let end = entry.quote.endDate, end > Date() else { continue }
        let status = try await api.start(
          plate: entry.quote.plate, zoneID: entry.quote.zoneID, tariff: entry.quote.tariff)
        guard revision == dataRevision else { return }
        guard let i = sessions.firstIndex(where: { $0.id == entry.id }) else { continue }
        sessions[i].lastChecked = Date()
        if entry.quote.isCovered(by: status, checkedAt: Date()) {
          sessions[i].state = .confirmed
          sessions[i].confirmationSource = .currentCoverage
          sessions[i].confirmedValidTill = status.t_start
          confirmed += 1
          await scheduleReminder(for: sessions[i])
        }
      } catch { errors.append(error.localizedDescription) }
    }
    checkMessage =
      errors.first
      ?? (confirmed > 0
        ? L("Сервис подтвердил оплаченное время парковки.")
        : L(
          "Оплата пока не подтверждена. Проверьте результат в банке; повторно оплачивать сразу не нужно."
        ))
  }
  private func scheduleReminder(for entry: ParkingSession) async {
    guard let end = entry.endDate, end.timeIntervalSinceNow > 600 else { return }
    let center = UNUserNotificationCenter.current()
    guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else {
      return
    }
    let content = UNMutableNotificationContent()
    content.title = L("Ещё 10 минут парковки")
    content.body =
      L(
        "%@ · %@. При необходимости продлите время.", String(describing: entry.quote.plate),
        String(describing: entry.quote.zoneTitle))
    content.sound = .default
    let trigger = UNTimeIntervalNotificationTrigger(
      timeInterval: end.timeIntervalSinceNow - 600, repeats: false)
    try? await center.add(
      UNNotificationRequest(identifier: entry.id.uuidString, content: content, trigger: trigger))
  }
  private func persist<T: Encodable>(_ value: T, key: String) {
    if let data = try? JSONEncoder().encode(value) {
      defaults.set(data, forKey: key)
    }
  }
  private static func restore<T: Decodable>(_ type: T.Type, key: String, defaults: UserDefaults)
    -> T?
  {
    guard let data = defaults.data(forKey: key) else { return nil }
    return try? JSONDecoder().decode(type, from: data)
  }
}

@MainActor
final class LocationService: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
  @Published var location: CLLocation?
  @Published var denied = false
  private let manager = CLLocationManager()
  override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
  }
  func request() {
    if manager.authorizationStatus == .notDetermined {
      manager.requestWhenInUseAuthorization()
    } else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
      denied = true
    } else {
      manager.startUpdatingLocation()
    }
  }
  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    denied = manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted
    if manager.authorizationStatus == .authorizedWhenInUse
      || manager.authorizationStatus == .authorizedAlways
    {
      manager.startUpdatingLocation()
    }
  }
  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    location = locations.last
  }
  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
